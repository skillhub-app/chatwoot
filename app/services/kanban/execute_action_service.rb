class Kanban::ExecuteActionService
  def initialize(execution)
    @execution  = execution
    @action     = execution.kanban_automation_action
    @automation = @action.kanban_automation
    @item       = execution.kanban_item
    @config     = @action.config.with_indifferent_access
  end

  def perform
    @execution.update!(status: 'running')

    unless should_execute?
      @execution.update!(status: 'skipped', executed_at: Time.current)
      log_activity('automation_skipped', reason: skip_reason)
      return
    end

    send("execute_#{@action.action_type}")
    @execution.update!(status: 'completed', executed_at: Time.current)
  rescue StandardError => e
    @execution.update!(status: 'failed', error_message: e.message, executed_at: Time.current)
    log_activity('automation_failed', error: e.message)
    raise
  end

  private

  def should_execute?
    @item.reload

    @skip_reason = nil

    if @automation.stop_on_stage_change && @item.stage_id != @automation.trigger_stage_id
      @skip_reason = 'lead_left_stage'
      return false
    end

    if @automation.stop_on_reply && @item.conversation_id.present?
      conversation = Conversation.find_by(id: @item.conversation_id)
      if conversation
        has_reply = conversation.messages
                                .where(message_type: :incoming)
                                .where('created_at > ?', @execution.scheduled_at)
                                .exists?
        if has_reply
          @skip_reason = 'lead_replied'
          return false
        end
      end
    end

    if @automation.stop_on_human_takeover && @item.conversation_id.present?
      conversation = Conversation.find_by(id: @item.conversation_id)
      if conversation&.assignee_id.present?
        @skip_reason = 'human_takeover'
        return false
      end
    end

    true
  end

  def skip_reason
    @skip_reason || 'unknown'
  end

  # ── WhatsApp ────────────────────────────────────────────────────────────────

  def execute_send_whatsapp
    conversation = Conversation.find_by(id: @item.conversation_id)
    unless conversation
      @execution.update!(result: { error: 'no_conversation' })
      return log_activity('automation_skipped', reason: 'no_conversation_linked')
    end

    unless conversation.inbox.channel_type == 'Channel::Whatsapp'
      @execution.update!(result: { error: 'not_whatsapp_channel' })
      return log_activity('automation_skipped', reason: 'not_whatsapp_channel')
    end

    if inside_business_hours?
      content = @config['use_ai'] ? generate_ai_message : @config['message']
      message = Messages::MessageBuilder.new(nil, conversation, { content: content, private: false }).perform
      log_activity('automation_message_sent', message_id: message.id, content: content)
      @execution.update!(result: { message_id: message.id })
    else
      @execution.update!(status: 'skipped', executed_at: Time.current, result: { error: 'outside_business_hours' })
      log_activity('automation_skipped', reason: 'outside_business_hours')
    end
  end

  def inside_business_hours?
    window = @config['window']
    return true unless window.present?

    hour = Time.current.in_time_zone.hour
    hour >= window['start_hour'].to_i && hour <= window['end_hour'].to_i
  end

  def generate_ai_message
    stage_name    = @automation.trigger_stage&.name
    contact_name  = @item.contact&.name || @item.contact_phone
    "Olá#{contact_name ? ", #{contact_name.split.first}" : ''}! Estamos acompanhando seu processo na etapa \"#{stage_name}\". Podemos te ajudar com algo?"
  end

  # ── Webhook ─────────────────────────────────────────────────────────────────

  def execute_send_webhook
    url    = build_webhook_url
    method = (@config['method'].presence || 'POST').upcase
    headers = build_webhook_headers
    body    = build_webhook_body

    conn = Faraday.new(url: url) do |f|
      f.options.timeout      = 15
      f.options.open_timeout = 5
    end

    response = conn.send(method.downcase.to_sym) do |req|
      headers.each { |k, v| req.headers[k] = v }
      req.body = body.to_json unless method == 'GET'
    end

    log_activity('automation_webhook_dispatched', url: url, status: response.status)
    @execution.update!(result: {
      url:           url,
      method:        method,
      status:        response.status,
      response_body: response.body.to_s.first(1000)
    })
  rescue StandardError => e
    log_activity('automation_webhook_failed', url: url, error: e.message)
    @execution.update!(result: { url: url, error: e.message })
    raise
  end

  def build_webhook_url
    url = @config['url'].to_s
    if @config['auth_type'] == 'api_key_query'
      key   = @config['auth_key_name'].presence || 'api_key'
      value = @config['auth_key_value'].to_s
      separator = url.include?('?') ? '&' : '?'
      url = "#{url}#{separator}#{CGI.escape(key)}=#{CGI.escape(value)}"
    end
    url
  end

  def build_webhook_headers
    headers = { 'Content-Type' => 'application/json' }

    custom = @config['headers']
    if custom.is_a?(Hash)
      custom.each { |k, v| headers[k.to_s] = interpolate_vars(v.to_s) }
    end

    case @config['auth_type']
    when 'bearer'
      headers['Authorization'] = "Bearer #{@config['auth_token']}"
    when 'basic'
      creds = Base64.strict_encode64("#{@config['auth_user']}:#{@config['auth_pass']}")
      headers['Authorization'] = "Basic #{creds}"
    when 'api_key_header'
      key = @config['auth_key_name'].presence || 'X-API-Key'
      headers[key] = @config['auth_key_value'].to_s
    end

    headers
  end

  def build_webhook_body
    base = @config['full_crm_payload'] ? build_full_crm_payload : { event: 'kanban.automation.triggered', timestamp: Time.current.iso8601, card_id: @item.id }

    raw_custom = @config['custom_payload']
    return base unless raw_custom.present?

    json_str = raw_custom.is_a?(String) ? raw_custom : raw_custom.to_json
    custom = JSON.parse(interpolate_vars(json_str))
    base.is_a?(Hash) ? base.merge(custom.deep_symbolize_keys) : custom
  rescue JSON::ParseError
    base
  end

  def build_full_crm_payload
    stage      = @automation.trigger_stage
    pipeline   = KanbanPipeline.find_by(id: @item.pipeline_id)
    contact    = @item.contact
    assignee   = @item.assignee_id ? User.find_by(id: @item.assignee_id) : nil
    conversation = @item.conversation_id ? Conversation.find_by(id: @item.conversation_id) : nil

    {
      event:                'kanban.automation.triggered',
      timestamp:            Time.current.iso8601,
      automation_action_id: @action.id,
      lead: {
        id:    contact&.id,
        name:  contact&.name,
        phone: @item.contact_phone,
        email: contact&.email
      },
      card: {
        id:         @item.id,
        title:      @item.title,
        value:      @item.value,
        status:     @item.status,
        won_at:     @item.won_at,
        lost_at:    @item.lost_at,
        created_at: @item.created_at
      },
      pipeline: {
        id:   pipeline&.id,
        name: pipeline&.name
      },
      stage: {
        id:    stage&.id,
        name:  stage&.name,
        color: stage&.color
      },
      owner: {
        id:    assignee&.id,
        name:  assignee&.name,
        email: assignee&.email
      },
      conversation: {
        id:       conversation&.id,
        status:   conversation&.status,
        inbox_id: conversation&.inbox_id
      },
      automation: {
        id:   @automation.id,
        name: @automation.name
      },
      account: {
        id: @item.account_id
      }
    }
  end

  def webhook_variables
    stage    = @automation.trigger_stage
    pipeline = KanbanPipeline.find_by(id: @item.pipeline_id)
    contact  = @item.contact
    assignee = @item.assignee_id ? User.find_by(id: @item.assignee_id) : nil
    conversation = @item.conversation_id ? Conversation.find_by(id: @item.conversation_id) : nil

    {
      'lead'         => { 'name' => contact&.name, 'phone' => @item.contact_phone, 'email' => contact&.email, 'id' => contact&.id.to_s },
      'card'         => { 'id' => @item.id.to_s, 'title' => @item.title, 'value' => @item.value.to_s, 'status' => @item.status },
      'pipeline'     => { 'id' => pipeline&.id.to_s, 'name' => pipeline&.name },
      'stage'        => { 'id' => stage&.id.to_s, 'name' => stage&.name },
      'owner'        => { 'id' => assignee&.id.to_s, 'name' => assignee&.name, 'email' => assignee&.email },
      'conversation' => { 'id' => conversation&.id.to_s }
    }
  end

  def interpolate_vars(text)
    vars = webhook_variables
    text.gsub(/\{\{\s*([\w.]+)\s*\}\}/) do
      parts = $1.split('.')
      val = parts.reduce(vars) { |h, k| h.is_a?(Hash) ? h[k] : nil }
      val.nil? ? "{{#{$1}}}" : val.to_s
    end
  end

  # ── Task ────────────────────────────────────────────────────────────────────

  def execute_create_task
    assignee_id = resolve_assignee(@config['assignee_type'], @config['assignee_id'])
    due_at = @config['due_offset_minutes'].present? ? @config['due_offset_minutes'].to_i.minutes.from_now : nil

    task = @item.kanban_tasks.create!(
      title:        @config['title'],
      description:  @config['description'],
      assignee_id:  assignee_id,
      priority:     (@config['priority'] || 0).to_i,
      due_at:       due_at
    )

    log_activity('automation_task_created', task_id: task.id, title: task.title,
                                            description: "Tarefa criada automaticamente: #{task.title}")
    @execution.update!(result: { task_id: task.id })
  end

  def resolve_assignee(assignee_type, assignee_id)
    case assignee_type
    when 'lead_owner' then @item.assignee_id
    when 'specific'   then assignee_id.to_i.positive? ? assignee_id.to_i : nil
    else nil
    end
  end

  # ── Helpers ─────────────────────────────────────────────────────────────────

  def log_activity(action_type, metadata = {})
    @item.kanban_activities.create!(
      action_type: action_type,
      metadata:    metadata.merge(
        automation_id:        @automation.id,
        automation_action_id: @action.id,
        action_type_label:    @action.action_type
      )
    )
  end
end

class Kanban::ExecuteActionService
  MESSAGING_CHANNELS = %w[Channel::Whatsapp Channel::Uazapi].freeze

  def initialize(execution)
    @execution       = execution
    @action          = execution.kanban_automation_action
    @automation      = @action.kanban_automation
    @item            = execution.kanban_item
    @config          = @action.config.with_indifferent_access
    @skip_reason     = nil
    @skip_description = nil
  end

  def perform
    @execution.update!(status: 'running')

    unless should_execute?
      @execution.update!(status: 'skipped', executed_at: Time.current)
      log_activity('automation_skipped', reason: skip_reason, description: @skip_description)
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

    if @automation.stop_on_stage_change && @item.stage_id != @automation.trigger_stage_id
      @skip_reason     = 'lead_left_stage'
      @skip_description = 'Card saiu da etapa antes da execução'
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
          @skip_reason     = 'lead_replied'
          @skip_description = 'Lead respondeu após o agendamento'
          return false
        end
      end
    end

    if @automation.stop_on_human_takeover && @item.conversation_id.present?
      conversation = Conversation.find_by(id: @item.conversation_id)
      if conversation&.assignee_id.present?
        @skip_reason     = 'human_takeover'
        @skip_description = 'Humano assumiu a conversa'
        return false
      end
    end

    true
  end

  def skip_reason
    @skip_reason || 'unknown'
  end

  # ── WhatsApp / UAZAPI ───────────────────────────────────────────────────────

  def execute_send_whatsapp
    conversation = find_conversation_for_message
    unless conversation
      @execution.update!(result: { error: 'no_conversation' })
      return log_activity('automation_skipped', reason: 'no_conversation_linked',
                          description: 'Sem conversa ativa vinculada ao card')
    end

    if conversation.cached_label_list_array.include?('ia_desligada')
      @execution.update!(result: { error: 'ia_paused' })
      return log_activity('automation_skipped', reason: 'ia_paused',
                          description: 'IA pausada na conversa (label ia_desligada ativa)')
    end

    target_inbox_id = @config['inbox_id'].present? ? @config['inbox_id'].to_i : nil

    if target_inbox_id && target_inbox_id != conversation.inbox_id && @config['open_new_conversation']
      conversation = open_conversation_in_inbox(target_inbox_id, conversation)
      return unless conversation
    end

    channel_type = conversation.inbox.channel_type
    unless MESSAGING_CHANNELS.include?(channel_type)
      @execution.update!(result: { error: 'not_supported_channel', channel: channel_type })
      return log_activity('automation_skipped', reason: 'not_supported_channel',
                          description: "Canal #{channel_type} não suporta envio automático")
    end

    unless inside_business_hours?
      @execution.update!(status: 'skipped', executed_at: Time.current, result: { error: 'outside_business_hours' })
      return log_activity('automation_skipped', reason: 'outside_business_hours',
                          description: 'Fora do horário comercial configurado')
    end

    content   = @config['use_ai'] ? generate_ai_message : interpolate_vars(@config['message'].to_s)
    send_mode = @config['send_mode'].presence || 'bot'
    agent_bot = send_mode == 'bot' ? find_agent_bot_for(conversation) : nil

    msg_params = { content: content, private: false }
    msg_params[:sender_type] = 'AgentBot' if agent_bot
    msg_params[:sender_id]   = agent_bot.id if agent_bot

    message = Messages::MessageBuilder.new(nil, conversation, msg_params).perform
    log_activity('automation_message_sent', message_id: message.id, content: content,
                 sender: agent_bot ? "bot:#{agent_bot.id}" : 'system',
                 description: "Mensagem enviada: #{content.to_s.first(100)}")
    @execution.update!(result: { message_id: message.id, sender: agent_bot ? 'bot' : 'system' })
  end

  def find_conversation_for_message
    return Conversation.find_by(id: @item.conversation_id) if @item.conversation_id.present?

    open_convs = Conversation.where(account_id: @item.account_id, status: :open).order(updated_at: :desc)

    if @item.contact_id.present?
      conv = open_convs.find_by(contact_id: @item.contact_id)
      return conv if conv
    end

    if @item.contact_phone.present?
      digits = @item.contact_phone.gsub(/\D/, '')
      contact = Contact.where(account_id: @item.account_id)
                       .where('phone_number LIKE ?', "%#{digits}%")
                       .first
      return open_convs.find_by(contact_id: contact.id) if contact
    end

    nil
  end

  def open_conversation_in_inbox(inbox_id, existing_conversation)
    inbox = Inbox.find_by(id: inbox_id, account_id: @item.account_id)
    return existing_conversation unless inbox

    contact = existing_conversation.contact || @item.contact
    return existing_conversation unless contact

    contact_inbox = ContactInbox.find_or_create_by!(contact: contact, inbox: inbox)
    new_conv = Conversation.create!(
      account:          @item.account,
      inbox:            inbox,
      contact:          contact,
      contact_inbox:    contact_inbox,
      status:           :open
    )

    if @config['new_conv_same_card']
      @item.update!(conversation_id: new_conv.id)
      log_activity('automation_new_conv_linked', conversation_id: new_conv.id, inbox_id: inbox_id)
    elsif @config['new_conv_pipeline_id'].present? && @config['new_conv_stage_id'].present?
      new_item = KanbanItem.create!(
        account_id:    @item.account_id,
        pipeline_id:   @config['new_conv_pipeline_id'].to_i,
        stage_id:      @config['new_conv_stage_id'].to_i,
        title:         @item.title,
        contact_phone: @item.contact_phone,
        assignee_id:   @item.assignee_id,
        contact:       contact,
        conversation_id: new_conv.id
      )
      log_activity('automation_new_item_for_conv', new_item_id: new_item.id, conversation_id: new_conv.id)
    end

    new_conv
  end

  def inside_business_hours?
    start_str = @config['business_hours_start'].presence
    end_str   = @config['business_hours_end'].presence

    # Legacy window format: { start_hour: 9, end_hour: 18 }
    if start_str.blank? && @config['window'].present?
      w = @config['window']
      start_str = w['start_hour'].to_s.rjust(2, '0') + ':00'
      end_str   = w['end_hour'].to_s.rjust(2, '0') + ':00'
    end

    return true unless start_str.present? && end_str.present?

    current = Time.current.in_time_zone.strftime('%H:%M')
    current >= start_str && current <= end_str
  end

  def find_agent_bot_for(conversation)
    AgentBotInbox.find_by(inbox_id: conversation.inbox_id)&.agent_bot
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

  # ── CRM Action ──────────────────────────────────────────────────────────────

  def execute_crm_action
    unless crm_conditions_match?
      log_activity('automation_crm_skipped', reason: 'conditions_not_met')
      @execution.update!(result: { skipped: 'conditions_not_met' })
      return
    end

    executed = []
    (@config['crm_actions'] || []).each do |action|
      run_crm_sub_action(action.with_indifferent_access, executed)
    end

    log_activity('automation_crm_executed', actions: executed)
    @execution.update!(result: { executed_actions: executed })
  end

  def crm_conditions_match?
    conditions = @config['conditions'] || []
    return true if conditions.empty?

    logic   = (@config['condition_logic'] || 'AND').upcase
    results = conditions.map { |c| evaluate_crm_condition(c.with_indifferent_access) }
    logic == 'AND' ? results.all? : results.any?
  end

  def evaluate_crm_condition(cond)
    attr  = cond['attribute'].to_s
    value = cond['value'].to_s

    case attr
    when 'lead_in_pipeline'     then @item.pipeline_id.to_s == value
    when 'lead_in_stage'        then @item.stage_id.to_s == value
    when 'lead_in_pipeline_and_stage'
      pid, sid = value.split(':')
      @item.pipeline_id.to_s == pid && @item.stage_id.to_s == sid
    when 'lead_assignee'        then @item.assignee_id.to_s == value
    when 'lead_status'          then @item.status == value
    when 'lead_has_pending_task'
      has_pending = @item.kanban_tasks.pending.exists?
      value == 'true' ? has_pending : !has_pending
    when 'lead_has_conversation'
      has_conv = @item.conversation_id.present?
      value == 'true' ? has_conv : !has_conv
    when 'lead_has_lost_reason' then @item.lost_reason_id.to_s == value
    when 'conversation_inbox'
      conv = Conversation.find_by(id: @item.conversation_id)
      conv&.inbox_id.to_s == value
    when 'conversation_label'
      conv = Conversation.find_by(id: @item.conversation_id)
      conv&.cached_label_list_array&.include?(value) || false
    when 'conversation_status'
      conv = Conversation.find_by(id: @item.conversation_id)
      conv&.status.to_s == value
    when 'conversation_channel'
      conv = Conversation.find_by(id: @item.conversation_id)
      conv&.inbox&.channel_type.to_s == value
    when 'message_contains'
      conv = Conversation.find_by(id: @item.conversation_id)
      last_msg = conv&.messages&.where(message_type: :incoming)&.order(:created_at)&.last
      last_msg&.content.to_s.downcase.include?(value.downcase)
    else true
    end
  end

  def run_crm_sub_action(action, executed)
    case action['type']
    when 'move_item'
      stage_id    = action['stage_id']&.to_i
      pipeline_id = action['pipeline_id']&.to_i
      return unless stage_id&.positive?

      attrs = { stage_id: stage_id }
      attrs[:pipeline_id] = pipeline_id if pipeline_id&.positive?
      @item.update!(attrs)
      executed << { type: 'move_item', stage_id: stage_id }
      log_activity('automation_crm_moved', stage_id: stage_id, pipeline_id: pipeline_id)

    when 'assign_agent'
      agent_id = action['agent_id']&.to_i
      return unless agent_id&.positive?

      @item.update!(assignee_id: agent_id)
      executed << { type: 'assign_agent', agent_id: agent_id }
      log_activity('automation_crm_assigned', agent_id: agent_id)

    when 'add_note'
      content = action['content'].to_s.strip
      return if content.blank?

      @item.kanban_notes.create!(content: content, author: nil)
      executed << { type: 'add_note' }
      log_activity('automation_crm_note_added', preview: content.first(80))

    when 'create_item'
      pipeline_id = action['pipeline_id']&.to_i
      stage_id    = action['stage_id']&.to_i
      return unless pipeline_id&.positive? && stage_id&.positive?

      title = action['title'].presence || @item.title
      new_item = KanbanItem.create!(
        account_id:    @item.account_id,
        pipeline_id:   pipeline_id,
        stage_id:      stage_id,
        title:         title,
        contact_phone: @item.contact_phone,
        assignee_id:   @item.assignee_id,
        contact:       @item.contact
      )
      executed << { type: 'create_item', new_item_id: new_item.id }
      log_activity('automation_crm_item_created', new_item_id: new_item.id, title: title)
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

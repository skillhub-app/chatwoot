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
    payload = build_webhook_payload
    WebhookJob.perform_later(@config['url'], payload)
    log_activity('automation_webhook_dispatched', url: @config['url'])
    @execution.update!(result: { url: @config['url'] })
  end

  def build_webhook_payload
    {
      event:                'kanban.automation.triggered',
      timestamp:            Time.current.iso8601,
      automation_action_id: @action.id,
      item: {
        id:             @item.id,
        title:          @item.title,
        stage_id:       @item.stage_id,
        pipeline_id:    @item.pipeline_id,
        value:          @item.value,
        contact_phone:  @item.contact_phone,
        assignee_id:    @item.assignee_id,
        status:         @item.status,
        won_at:         @item.won_at,
        lost_at:        @item.lost_at
      },
      custom_payload: @config['payload'] || {}
    }
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

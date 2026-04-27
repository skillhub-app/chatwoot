class Kanban::ConversationEventService
  def initialize(conversation, event_type)
    @conversation = conversation
    @event_type   = event_type
    @account_id   = conversation.account_id
  end

  def perform
    find_matching_actions.each { |action| execute_action(action) }
  end

  private

  def find_matching_actions
    pipeline_ids = KanbanPipeline.where(account_id: @account_id).select(:id)

    KanbanAutomationAction
      .joins(:kanban_automation)
      .where(action_type: 'crm_action', active: true)
      .where("config->>'event' = ?", @event_type)
      .where(kanban_automations: { active: true, pipeline_id: pipeline_ids })
  end

  def execute_action(action)
    config = action.config.with_indifferent_access
    return unless conditions_match?(config['conditions'] || [], config['condition_logic'])

    (config['crm_actions'] || []).each { |sub| run_sub_action(sub.with_indifferent_access) }
  rescue StandardError => e
    Rails.logger.error "Kanban::ConversationEventService error: #{e.message}"
  end

  def conditions_match?(conditions, logic)
    return true if conditions.empty?

    logic   = (logic || 'AND').upcase
    results = conditions.map { |c| evaluate_condition(c.with_indifferent_access) }
    logic == 'AND' ? results.all? : results.any?
  end

  def evaluate_condition(cond)
    attr  = cond['attribute'].to_s
    value = cond['value'].to_s

    case attr
    when 'conversation_inbox'   then @conversation.inbox_id.to_s == value
    when 'conversation_status'  then @conversation.status.to_s == value
    when 'conversation_channel' then @conversation.inbox&.channel_type.to_s == value
    when 'conversation_label'   then @conversation.cached_label_list_array&.include?(value) || false
    else true
    end
  end

  def run_sub_action(sub)
    return unless sub['type'] == 'create_item'

    pipeline_id = sub['pipeline_id']&.to_i
    stage_id    = sub['stage_id']&.to_i
    return unless pipeline_id&.positive? && stage_id&.positive?

    contact = @conversation.contact
    title   = sub['title'].presence ||
              contact&.name.presence ||
              "Conversa ##{@conversation.id}"

    KanbanItem.create!(
      account_id:      @account_id,
      pipeline_id:     pipeline_id,
      stage_id:        stage_id,
      title:           title,
      contact_phone:   contact&.phone_number,
      contact:         contact,
      conversation_id: @conversation.id
    )
  end
end

class AutomationRules::KanbanConditionsService
  KANBAN_ATTRIBUTE_KEYS = %w[kanban_stage_id kanban_pipeline_id].freeze

  def self.has_kanban_conditions?(rule)
    rule.conditions.any? { |c| KANBAN_ATTRIBUTE_KEYS.include?(c['attribute_key']) }
  end

  def initialize(rule, conversation)
    @rule = rule
    @conversation = conversation
  end

  def perform
    kanban_conditions = @rule.conditions.select do |c|
      KANBAN_ATTRIBUTE_KEYS.include?(c['attribute_key'])
    end
    return true if kanban_conditions.empty?

    item = KanbanItem.find_by(conversation_id: @conversation.id)
    unless item
      Rails.logger.debug "[AutomationRule] Conversation ##{@conversation.id} without kanban_item — skipping rule ##{@rule.id}"
      return false
    end

    kanban_conditions.all? { |cond| evaluate_single(cond.with_indifferent_access, item) }
  end

  private

  def evaluate_single(condition, item)
    key      = condition[:attribute_key]
    operator = condition[:filter_operator]
    values   = Array(condition[:values]).map(&:to_s)

    actual = case key
             when 'kanban_stage_id'    then item.stage_id.to_s
             when 'kanban_pipeline_id' then item.pipeline_id.to_s
             end

    case operator
    when 'equal_to'     then values.include?(actual)
    when 'not_equal_to' then !values.include?(actual)
    else true
    end
  end
end

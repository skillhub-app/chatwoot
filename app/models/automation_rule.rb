# == Schema Information
#
# Table name: automation_rules
#
#  id          :bigint           not null, primary key
#  actions     :jsonb            not null
#  active      :boolean          default(TRUE), not null
#  conditions  :jsonb            not null
#  description :text
#  event_name  :string           not null
#  name        :string           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :bigint           not null
#
# Indexes
#
#  index_automation_rules_on_account_id  (account_id)
#
class AutomationRule < ApplicationRecord
  include Rails.application.routes.url_helpers
  include Reauthorizable

  belongs_to :account
  has_many_attached :files

  validate :json_conditions_format
  validate :json_actions_format
  validate :query_operator_presence
  validate :query_operator_value
  validates :account_id, presence: true

  after_update_commit :reauthorized!, if: -> { saved_change_to_conditions? }

  scope :active, -> { where(active: true) }

  def conditions_attributes
    %w[content email country_code status message_type browser_language assignee_id team_id referer city company inbox_id
       mail_subject phone_number priority conversation_language labels private_note
       kanban_stage_id kanban_pipeline_id]
  end

  def actions_attributes
    %w[send_message add_label remove_label send_email_to_team assign_team assign_agent remove_assigned_agent
       remove_assigned_team send_webhook_event mute_conversation send_attachment change_status resolve_conversation
       open_conversation pending_conversation snooze_conversation change_priority send_email_transcript
       add_private_note move_kanban_stage].freeze
  end

  def file_base_data
    files.map do |file|
      {
        id: file.id,
        automation_rule_id: id,
        file_type: file.content_type,
        account_id: account_id,
        file_url: url_for(file),
        blob_id: file.blob_id,
        filename: file.filename.to_s
      }
    end
  end

  private

  def json_conditions_format
    return if conditions.blank?

    attributes = conditions.map { |obj, _| obj['attribute_key'] }
    invalid = attributes - conditions_attributes
    invalid -= account.custom_attribute_definitions.pluck(:attribute_key)
    errors.add(:conditions, "Automation conditions #{invalid.join(',')} not supported.") if invalid.any?

    conditions.each do |cond|
      case cond['attribute_key']
      when 'kanban_stage_id'
        Array(cond['values']).each { |id| validate_kanban_stage_ownership(id) }
      when 'kanban_pipeline_id'
        Array(cond['values']).each { |id| validate_kanban_pipeline_ownership(id) }
      end
    end
  end

  def json_actions_format
    return if actions.blank?

    attributes = actions.map { |obj, _| obj['action_name'] }
    invalid = attributes - actions_attributes
    errors.add(:actions, "Automation actions #{invalid.join(',')} not supported.") if invalid.any?

    actions.each do |action|
      next unless action['action_name'] == 'move_kanban_stage'

      stage_id = Array(action['action_params']).first.to_i
      validate_kanban_stage_ownership(stage_id)
    end
  end

  def validate_kanban_stage_ownership(stage_id)
    stage = KanbanStage.find_by(id: stage_id)
    if stage.nil?
      errors.add(:conditions, "Etapa ##{stage_id} não encontrada")
    elsif stage.account_id != account_id
      errors.add(:conditions, 'Etapa não pertence à sua conta')
    end
  end

  def validate_kanban_pipeline_ownership(pipeline_id)
    pipeline = KanbanPipeline.find_by(id: pipeline_id)
    if pipeline.nil?
      errors.add(:conditions, "Funil ##{pipeline_id} não encontrado")
    elsif pipeline.account_id != account_id
      errors.add(:conditions, 'Funil não pertence à sua conta')
    end
  end

  def query_operator_presence
    return if conditions.blank?

    operators = conditions.select { |obj, _| obj['query_operator'].nil? }
    errors.add(:conditions, 'Automation conditions should have query operator.') if operators.length > 1
  end

  # This validation ensures logical operators are being used correctly in automation conditions.
  # And we don't push any unsanitized query operators to the database.
  def query_operator_value
    conditions.each do |obj|
      validate_single_condition(obj)
    end
  end

  def validate_single_condition(condition)
    query_operator = condition['query_operator']

    return if query_operator.nil?
    return if query_operator.empty?

    operator = query_operator.upcase
    errors.add(:conditions, 'Query operator must be either "AND" or "OR"') unless %w[AND OR].include?(operator)
  end
end

AutomationRule.include_mod_with('Audit::AutomationRule')
AutomationRule.prepend_mod_with('AutomationRule')

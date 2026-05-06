class AiAgent::ToolExecution < ApplicationRecord
  STATUSES = %w[success error timeout].freeze

  belongs_to :ai_agent
  belongs_to :ai_agent_execution, optional: true
  belongs_to :ai_agent_tool,      class_name: 'AiAgent::Tool', optional: true

  validates :tool_name, presence: true
  validates :status,    inclusion: { in: STATUSES }

  scope :ordered,   -> { order(created_at: :desc) }
  scope :success,   -> { where(status: 'success') }
  scope :failed,    -> { where(status: %w[error timeout]) }
  scope :for_agent, ->(agent_id) { where(ai_agent_id: agent_id) }
end

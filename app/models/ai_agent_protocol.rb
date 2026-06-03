class AiAgentProtocol < ApplicationRecord
  PROTOCOL_TYPES = %w[human qualified meeting unqualified custom].freeze
  PROTOCOL_ACTIONS = %w[continue pause_for_human end_conversation pause_temporary].freeze

  belongs_to :ai_agent

  validates :protocol_type, inclusion: { in: PROTOCOL_TYPES }
  validates :label,   presence: true
  validates :keyword, presence: true
  validates :action,  inclusion: { in: PROTOCOL_ACTIONS }

  default_scope { order(position: :asc) }
end

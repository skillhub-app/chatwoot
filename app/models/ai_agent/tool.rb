class AiAgent::Tool < ApplicationRecord
  HTTP_METHODS = %w[GET POST PUT PATCH DELETE].freeze

  belongs_to :ai_agent
  has_many :tool_executions, class_name: 'AiAgent::ToolExecution', dependent: :destroy

  validates :name,         presence: true, length: { maximum: 64 },
                           format: { with: /\A[a-z][a-z0-9_]*\z/, message: 'must be snake_case (lowercase letters, digits, underscores, starting with a letter)' }
  validates :name,         uniqueness: { scope: :ai_agent_id, message: 'already used in this agent' }
  validates :description,  presence: true
  validates :endpoint_url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), message: 'must be a valid URL' }
  validates :http_method,  inclusion: { in: HTTP_METHODS }
  validates :timeout_seconds, numericality: { greater_than: 0, less_than_or_equal_to: 60 }
  validate  :parameters_schema_valid

  scope :active,   -> { where(active: true) }
  scope :inactive, -> { where(active: false) }
  scope :ordered,  -> { order(:position, :name) }

  def to_function_definition
    {
      name:        name,
      description: full_description,
      parameters:  parameters_schema.presence || { type: 'object', properties: {} }
    }
  end

  def full_description
    [description, when_to_use.presence].compact.join(' | ')
  end

  private

  def parameters_schema_valid
    return if parameters_schema.blank?
    return if parameters_schema.is_a?(Hash) && parameters_schema['type'].present?

    errors.add(:parameters_schema, 'must be a valid JSON Schema object with a "type" key')
  rescue StandardError
    errors.add(:parameters_schema, 'is not valid JSON Schema')
  end
end

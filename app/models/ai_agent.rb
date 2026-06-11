class AiAgent < ApplicationRecord
  ALLOWED_MODELS_BY_PROVIDER = {
    'openai' => %w[gpt-4o gpt-4o-mini gpt-4-turbo],
    'anthropic' => %w[claude-opus-4-7 claude-sonnet-4-6 claude-haiku-4-5-20251001],
    'gemini' => %w[gemini-2.0-flash gemini-2.0-flash-lite gemini-1.5-pro gemini-1.5-flash gemini-3-flash-preview],
  }.freeze

  belongs_to :account
  belongs_to :inbox, optional: true
  belongs_to :llm_credential, class_name: 'LlmProviderCredential', optional: true

  has_many :ai_agent_prompt_versions, dependent: :destroy
  has_many :ai_agent_protocols,       dependent: :destroy
  has_many :ai_agent_faqs,            dependent: :destroy
  has_many :ai_agent_conversations,   dependent: :destroy
  has_many :ai_agent_executions,      dependent: :destroy
  has_many :tools,                    class_name: 'AiAgent::Tool',          dependent: :destroy
  has_many :tool_executions,          class_name: 'AiAgent::ToolExecution', dependent: :destroy
  has_one  :ai_agent_schedule,        dependent: :destroy

  validates :name, presence: true, length: { maximum: 255 }
  validates :inbox_id, uniqueness: { scope: :account_id }, allow_nil: true
  validates :message_buffer_seconds, numericality: { greater_than_or_equal_to: 10 }
  validates :memory_window_messages, numericality: { in: 10..500 }
  validate :llm_model_must_be_allowed_for_provider

  scope :active,   -> { where(active: true) }
  scope :inactive, -> { where(active: false) }

  def publish_prompt!(new_prompt, user = nil)
    new_version = prompt_version + 1
    ai_agent_prompt_versions.create!(
      version:    new_version,
      prompt:     new_prompt,
      created_by: user
    )
    update!(prompt: new_prompt, prompt_version: new_version, prompt_draft: {})
  end

  def save_draft!(draft_prompt)
    update!(prompt_draft: draft_prompt)
  end

  def has_draft?
    prompt_draft.present? && prompt_draft.any?
  end

  # Key efetiva: credential centralizada com fallback pro campo legado
  def effective_api_key
    return llm_credential.api_key if llm_credential.present?

    llm_api_key_encrypted
  end

  private

  def llm_model_must_be_allowed_for_provider
    return if llm_provider.blank? || llm_model.blank?

    allowed = ALLOWED_MODELS_BY_PROVIDER[llm_provider]

    if allowed.nil?
      errors.add(:llm_provider, 'não é um provider suportado')
      return
    end

    return if allowed.include?(llm_model)

    errors.add(
      :llm_model,
      "'#{llm_model}' não é suportado para o provider " \
      "'#{llm_provider}'. Modelos válidos: #{allowed.join(', ')}"
    )
  end
end

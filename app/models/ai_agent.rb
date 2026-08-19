class AiAgent < ApplicationRecord
  ALLOWED_MODELS_BY_PROVIDER = {
    'openai' => %w[gpt-5.5 gpt-5.4 gpt-5.4-mini gpt-5.4-nano gpt-5.1 gpt-4.1 gpt-4.1-mini gpt-4o gpt-4o-mini],
    'anthropic' => %w[claude-opus-4-8 claude-sonnet-4-6 claude-haiku-4-5],
    'gemini' => %w[gemini-3.5-flash gemini-3.1-flash-lite gemini-2.5-pro gemini-2.5-flash gemini-2.5-flash-lite
                   gemini-3.1-pro-preview gemini-3-flash-preview],
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

  def effective_api_key
    # 1. FK explícita + provider compatível
    return llm_credential.api_key if llm_credential.present? && llm_credential.provider == llm_provider

    # 2. Auto-wiring: busca credential por account + provider atual
    cred = account.llm_provider_credentials.find_by(provider: llm_provider)
    return cred.api_key if cred.present?

    # 3. Fallback legado
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

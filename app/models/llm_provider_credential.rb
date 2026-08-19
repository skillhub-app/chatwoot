# == Schema Information
#
# Table name: llm_provider_credentials
#
#  id         :bigint           not null, primary key
#  api_key    :text             not null
#  provider   :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#
# Indexes
#
#  index_llm_provider_credentials_on_account_id               (account_id)
#  index_llm_provider_credentials_on_account_id_and_provider  (account_id,provider) UNIQUE
#
class LlmProviderCredential < ApplicationRecord
  PROVIDERS = %w[openai anthropic gemini].freeze

  encrypts :api_key, deterministic: true if Chatwoot.encryption_configured?

  belongs_to :account
  has_many :ai_agents, foreign_key: :llm_credential_id, dependent: :nullify

  validates :provider, presence: true, inclusion: { in: PROVIDERS }
  validates :provider, uniqueness: { scope: :account_id }
  validates :api_key, presence: true
end

FactoryBot.define do
  factory :llm_provider_credential do
    account
    provider { 'openai' }
    api_key  { 'sk-test-key' }
  end
end

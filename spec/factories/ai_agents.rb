FactoryBot.define do
  factory :ai_agent do
    account
    sequence(:name) { |n| "Agente #{n}" }
    language              { 'pt-BR' }
    llm_provider          { 'openai' }
    llm_model             { 'gpt-4o' }
    active                { true }
    message_buffer_seconds { 20 }
    prompt                { {} }
  end
end

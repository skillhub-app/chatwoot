# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260610000003_migrate_existing_llm_keys.rb')

RSpec.describe MigrateExistingLlmKeys do
  let(:account) { create(:account) }
  let(:migration) { described_class.new }

  it 'cria credential a partir de agente com key' do
    agent = create(:ai_agent, account: account, llm_provider: 'openai', llm_api_key_encrypted: 'sk-abc')

    expect { migration.up }.to change(LlmProviderCredential, :count).by(1)

    credential = LlmProviderCredential.find_by(account: account, provider: 'openai')
    expect(credential.api_key).to eq('sk-abc')
    expect(agent.reload.llm_credential_id).to eq(credential.id)
  end

  it 'cria uma única credential pra múltiplos agentes do mesmo provider/account' do
    create(:ai_agent, account: account, llm_provider: 'openai', llm_api_key_encrypted: 'sk-abc')
    create(:ai_agent, account: account, llm_provider: 'openai', llm_api_key_encrypted: 'sk-abc')

    expect { migration.up }.to change(LlmProviderCredential, :count).by(1)
  end

  it 'em conflito de keys loga warning e usa a mais recente' do
    create(:ai_agent, account: account, llm_provider: 'openai',
                      llm_api_key_encrypted: 'sk-old', updated_at: 2.days.ago)
    create(:ai_agent, account: account, llm_provider: 'openai',
                      llm_api_key_encrypted: 'sk-new', updated_at: 1.hour.ago)

    allow(Rails.logger).to receive(:warn)
    migration.up

    expect(Rails.logger).to have_received(:warn).with(/Conflict.*openai/)
    expect(LlmProviderCredential.find_by(account: account, provider: 'openai').api_key).to eq('sk-new')
  end

  it 'aponta agentes sem key do mesmo provider pra credential criada' do
    create(:ai_agent, account: account, llm_provider: 'openai', llm_api_key_encrypted: 'sk-abc')
    keyless = create(:ai_agent, account: account, llm_provider: 'openai', llm_api_key_encrypted: nil)

    migration.up

    credential = LlmProviderCredential.find_by(account: account, provider: 'openai')
    expect(keyless.reload.llm_credential_id).to eq(credential.id)
  end

  it 'não cria credential pra agentes sem key' do
    create(:ai_agent, account: account, llm_provider: 'openai', llm_api_key_encrypted: nil)

    expect { migration.up }.not_to change(LlmProviderCredential, :count)
  end

  it 'é idempotente — rodar duas vezes não duplica nem quebra' do
    create(:ai_agent, account: account, llm_provider: 'openai', llm_api_key_encrypted: 'sk-abc')

    migration.up
    expect { migration.up }.not_to change(LlmProviderCredential, :count)
  end
end

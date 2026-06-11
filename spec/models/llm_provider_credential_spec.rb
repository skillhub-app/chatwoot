# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LlmProviderCredential do
  let(:account) { create(:account) }

  it 'aceita providers válidos' do
    %w[openai anthropic gemini].each do |provider|
      credential = described_class.new(account: account, provider: provider, api_key: 'key')
      expect(credential).to be_valid
    end
  end

  it 'rejeita provider fora da lista' do
    credential = described_class.new(account: account, provider: 'cohere', api_key: 'key')
    expect(credential).not_to be_valid
    expect(credential.errors[:provider]).to be_present
  end

  it 'rejeita provider duplicado na mesma account' do
    create(:llm_provider_credential, account: account, provider: 'openai')
    duplicate = described_class.new(account: account, provider: 'openai', api_key: 'other')
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:provider]).to be_present
  end

  it 'permite mesmo provider em accounts diferentes' do
    create(:llm_provider_credential, account: account, provider: 'openai')
    other = described_class.new(account: create(:account), provider: 'openai', api_key: 'key')
    expect(other).to be_valid
  end

  it 'rejeita api_key em branco' do
    credential = described_class.new(account: account, provider: 'openai', api_key: '')
    expect(credential).not_to be_valid
    expect(credential.errors[:api_key]).to be_present
  end

  it 'destroy anula llm_credential_id dos agentes vinculados' do
    credential = create(:llm_provider_credential, account: account, provider: 'openai')
    agent = create(:ai_agent, account: account, llm_credential: credential)
    credential.destroy!
    expect(agent.reload.llm_credential_id).to be_nil
  end
end

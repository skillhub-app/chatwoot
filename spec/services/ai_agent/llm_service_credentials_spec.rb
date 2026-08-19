# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiAgent::LlmService do
  let(:account) { create(:account) }
  let(:prompt) { { system: 'sys', messages: [{ role: 'user', content: 'oi' }] } }

  def stub_openai
    stub_request(:post, 'https://api.openai.com/v1/chat/completions')
      .to_return(
        status: 200,
        headers: { 'Content-Type' => 'application/json' },
        body: { choices: [{ message: { content: 'ok' } }] }.to_json
      )
  end

  it 'usa a credential centralizada quando o agente tem llm_credential' do
    credential = create(:llm_provider_credential, account: account, provider: 'openai', api_key: 'central-key')
    agent = create(:ai_agent, account: account, llm_credential: credential, llm_api_key_encrypted: nil)
    stub = stub_openai

    described_class.call(agent, prompt)

    expect(stub.with(headers: { 'Authorization' => 'Bearer central-key' })).to have_been_requested
  end

  it 'faz fallback pra llm_api_key_encrypted quando sem credential' do
    agent = create(:ai_agent, account: account, llm_api_key_encrypted: 'legacy-key')
    stub = stub_openai

    described_class.call(agent, prompt)

    expect(stub.with(headers: { 'Authorization' => 'Bearer legacy-key' })).to have_been_requested
  end

  it 'prefere a credential mesmo quando o campo legado está preenchido' do
    credential = create(:llm_provider_credential, account: account, provider: 'openai', api_key: 'central-key')
    agent = create(:ai_agent, account: account, llm_credential: credential, llm_api_key_encrypted: 'legacy-key')
    stub = stub_openai

    described_class.call(agent, prompt)

    expect(stub.with(headers: { 'Authorization' => 'Bearer central-key' })).to have_been_requested
  end

  it 'levanta erro útil quando não há credential nem key local' do
    agent = create(:ai_agent, account: account, llm_api_key_encrypted: nil)

    expect { described_class.call(agent, prompt) }
      .to raise_error(ArgumentError, /LLM API key not configured/)
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiAgentProtocol do
  let(:account) { create(:account) }
  let(:agent) do
    AiAgent.create!(
      account: account, name: 'Clara', language: 'pt', active: true,
      llm_provider: 'openai', llm_model: 'gpt-4o-mini',
      llm_api_key_encrypted: 'test-key'
    )
  end

  def build_protocol(overrides = {})
    AiAgentProtocol.new(
      { ai_agent: agent, protocol_type: 'human', label: 'Humano',
        keyword: '#HUMANO', position: 0 }.merge(overrides)
    )
  end

  describe 'validations' do
    it 'é válido com atributos corretos' do
      expect(build_protocol).to be_valid
    end

    it 'valida presença de label' do
      expect(build_protocol(label: '')).not_to be_valid
    end

    it 'valida presença de keyword' do
      expect(build_protocol(keyword: '')).not_to be_valid
    end

    it 'valida inclusion de protocol_type' do
      expect(build_protocol(protocol_type: 'invalido')).not_to be_valid
    end

    it 'valida inclusion de action' do
      expect(build_protocol(action: 'invalido')).not_to be_valid
    end

    it 'rejeita action nil' do
      p = build_protocol
      p.action = nil
      expect(p).not_to be_valid
    end
  end

  describe 'defaults' do
    it "action padrão é 'pause_for_human'" do
      p = AiAgentProtocol.create!(
        ai_agent: agent, protocol_type: 'human', label: 'H', keyword: '#H', position: 0
      )
      expect(p.action).to eq('pause_for_human')
    end

    it "auto_summarize padrão é true" do
      p = AiAgentProtocol.create!(
        ai_agent: agent, protocol_type: 'human', label: 'H', keyword: '#H', position: 0
      )
      expect(p.auto_summarize).to be(true)
    end
  end

  describe 'PROTOCOL_ACTIONS' do
    it 'contém os 4 valores esperados' do
      expect(described_class::PROTOCOL_ACTIONS).to contain_exactly(
        'continue', 'pause_for_human', 'end_conversation', 'pause_temporary'
      )
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiAgent do
  let(:account) { create(:account) }

  def build_agent(provider:, model:)
    described_class.new(
      account:                 account,
      name:                    'Test Agent',
      llm_provider:            provider,
      llm_model:               model,
      message_buffer_seconds:  30,
      memory_window_messages:  100
    )
  end

  context 'llm model validation' do
    it 'aceita gemini-3-flash-preview com provider gemini' do
      agent = build_agent(provider: 'gemini', model: 'gemini-3-flash-preview')
      expect(agent).to be_valid
    end

    it 'aceita gpt-4o com provider openai' do
      agent = build_agent(provider: 'openai', model: 'gpt-4o')
      expect(agent).to be_valid
    end

    it 'aceita claude-opus-4-7 com provider anthropic' do
      agent = build_agent(provider: 'anthropic', model: 'claude-opus-4-7')
      expect(agent).to be_valid
    end

    it 'rejeita modelo inválido com mensagem 422 clara' do
      agent = build_agent(provider: 'openai', model: 'foo-bar')
      expect(agent).not_to be_valid
      expect(agent.errors[:llm_model].first).to include("'foo-bar' não é suportado")
      expect(agent.errors[:llm_model].first).to include('openai')
      expect(agent.errors[:llm_model].first).to include('gpt-4o')
    end

    it 'rejeita gemini-3-flash-preview com provider openai' do
      agent = build_agent(provider: 'openai', model: 'gemini-3-flash-preview')
      expect(agent).not_to be_valid
      expect(agent.errors[:llm_model].first).to include("'gemini-3-flash-preview' não é suportado")
    end

    it 'rejeita provider não suportado' do
      agent = build_agent(provider: 'cohere', model: 'command-r')
      expect(agent).not_to be_valid
      expect(agent.errors[:llm_provider].first).to include('não é um provider suportado')
    end

    it 'permite llm_model em branco (não força)' do
      agent = build_agent(provider: 'openai', model: '')
      agent.valid?
      expect(agent.errors[:llm_model]).to be_empty
    end

    it 'permite llm_provider em branco (não força)' do
      agent = build_agent(provider: '', model: 'gpt-4o')
      agent.valid?
      expect(agent.errors[:llm_provider]).to be_empty
    end
  end
end

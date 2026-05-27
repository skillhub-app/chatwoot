# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiAgent::ConversationSummaryService do
  let(:account)      { create(:account) }
  let(:inbox)        { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  let(:agent) do
    AiAgent.create!(
      account: account, name: 'Clara', language: 'pt', active: true,
      llm_provider: 'openai', llm_model: 'gpt-4o-mini',
      llm_api_key_encrypted: 'test-key'
    )
  end

  let(:llm_response) do
    AiAgent::LlmService::LlmResponse.new(
      type: :text,
      text: 'Lead perguntou sobre preços. Proposta enviada. Aguardando retorno.',
      tool_calls: [], raw_parts: nil
    )
  end

  subject(:service) { described_class.new(agent, conversation) }

  describe '#call' do
    context 'conversa vazia (sem mensagens)' do
      it 'retorna mensagem padrão sem chamar LLM' do
        allow(AiAgent::LlmService).to receive(:call)
        result = service.call
        expect(result).to eq('Lead não interagiu — sem mensagens para resumir.')
        expect(AiAgent::LlmService).not_to have_received(:call)
      end
    end

    context 'com 5 mensagens na conversa' do
      before do
        3.times { |i| create(:message, conversation: conversation, message_type: :incoming, content: "msg lead #{i}") }
        2.times { |i| create(:message, conversation: conversation, message_type: :outgoing, content: "msg agente #{i}") }
      end

      it 'chama LLM com as 5 mensagens no histórico e retorna o texto' do
        allow(AiAgent::LlmService).to receive(:call).and_return(llm_response)
        result = service.call
        expect(result).to eq('Lead perguntou sobre preços. Proposta enviada. Aguardando retorno.')
        expect(AiAgent::LlmService).to have_received(:call) do |_agent, prompt, **|
          expect(prompt[:messages].length).to eq(5)
        end
      end
    end

    context 'com 100 mensagens na conversa' do
      before do
        100.times { |i| create(:message, conversation: conversation, message_type: :incoming, content: "msg #{i}") }
      end

      it 'limita o histórico a 50 mensagens' do
        allow(AiAgent::LlmService).to receive(:call).and_return(llm_response)
        service.call
        expect(AiAgent::LlmService).to have_received(:call) do |_agent, prompt, **|
          expect(prompt[:messages].length).to eq(50)
        end
      end
    end

    context 'com notas privadas na conversa' do
      before do
        create(:message, conversation: conversation, message_type: :outgoing, content: 'pública', private: false)
        create(:message, conversation: conversation, message_type: :outgoing, content: 'privada', private: true)
      end

      it 'exclui notas privadas do histórico' do
        allow(AiAgent::LlmService).to receive(:call).and_return(llm_response)
        service.call
        expect(AiAgent::LlmService).to have_received(:call) do |_agent, prompt, **|
          contents = prompt[:messages].map { |m| m[:content] }
          expect(contents).to include('pública')
          expect(contents).not_to include('privada')
        end
      end
    end

    context 'quando LLM retorna texto vazio' do
      before { create(:message, conversation: conversation, message_type: :incoming, content: 'oi') }

      it 'retorna nil' do
        empty = AiAgent::LlmService::LlmResponse.new(type: :text, text: '', tool_calls: [], raw_parts: nil)
        allow(AiAgent::LlmService).to receive(:call).and_return(empty)
        expect(service.call).to be_nil
      end
    end

    context 'quando LLM levanta exceção' do
      before { create(:message, conversation: conversation, message_type: :incoming, content: 'oi') }

      it 'captura o erro, loga e retorna nil (fallback graceful)' do
        allow(AiAgent::LlmService).to receive(:call).and_raise(StandardError, 'timeout')
        expect(Rails.logger).to receive(:error).with(/SummaryAI.*timeout/)
        expect(service.call).to be_nil
      end
    end

    context 'quando LLM retorna texto maior que 2000 chars' do
      before { create(:message, conversation: conversation, message_type: :incoming, content: 'oi') }

      it 'trunca em 2000 caracteres' do
        long = AiAgent::LlmService::LlmResponse.new(type: :text, text: 'x' * 3000, tool_calls: [], raw_parts: nil)
        allow(AiAgent::LlmService).to receive(:call).and_return(long)
        expect(service.call.length).to eq(2000)
      end
    end

    context 'agente com provider Gemini' do
      let(:gemini_agent) do
        AiAgent.create!(
          account: account, name: 'Gemini Bot', language: 'pt', active: true,
          llm_provider: 'gemini', llm_model: 'gemini-2.0-flash',
          llm_api_key_encrypted: 'gemini-key'
        )
      end

      before { create(:message, conversation: conversation, message_type: :incoming, content: 'oi') }

      it 'passa o agente Gemini ao LlmService (adapter correto)' do
        allow(AiAgent::LlmService).to receive(:call).and_return(llm_response)
        described_class.new(gemini_agent, conversation).call
        expect(AiAgent::LlmService).to have_received(:call) do |agent_arg, _prompt, **|
          expect(agent_arg.llm_provider).to eq('gemini')
        end
      end
    end

    context 'agente com provider Anthropic' do
      let(:anthropic_agent) do
        AiAgent.create!(
          account: account, name: 'Claude Bot', language: 'pt', active: true,
          llm_provider: 'anthropic', llm_model: 'claude-3-haiku-20240307',
          llm_api_key_encrypted: 'anthropic-key'
        )
      end

      before { create(:message, conversation: conversation, message_type: :incoming, content: 'oi') }

      it 'passa o agente Anthropic ao LlmService (adapter correto)' do
        allow(AiAgent::LlmService).to receive(:call).and_return(llm_response)
        described_class.new(anthropic_agent, conversation).call
        expect(AiAgent::LlmService).to have_received(:call) do |agent_arg, _prompt, **|
          expect(agent_arg.llm_provider).to eq('anthropic')
        end
      end
    end

    context 'system prompt' do
      before { create(:message, conversation: conversation, message_type: :incoming, content: 'oi') }

      it 'inclui orientação de tamanho máximo de 5 linhas' do
        allow(AiAgent::LlmService).to receive(:call).and_return(llm_response)
        service.call
        expect(AiAgent::LlmService).to have_received(:call) do |_agent, prompt, **|
          expect(prompt[:system]).to include('5 linhas')
        end
      end
    end
  end
end

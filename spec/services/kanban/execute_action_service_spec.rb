# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Kanban::ExecuteActionService do
  let(:account)      { create(:account) }
  let(:contact)      { create(:contact, account: account, phone_number: '+5511999990000') }
  let(:inbox)        { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, status: :open) }
  let(:pipeline) do
    KanbanPipeline.create!(account: account, name: 'Vendas', position: 0, visibility_type: 'all')
  end
  let(:stage) do
    KanbanStage.create!(pipeline: pipeline, name: 'Proposta', position: 0, probability: 50)
  end
  let(:item) do
    KanbanItem.create!(
      account: account, pipeline: pipeline, stage: stage,
      title: 'Lead Teste', position: 0,
      contact: contact, contact_phone: contact.phone_number,
      conversation: conversation
    )
  end
  let(:automation) do
    KanbanAutomation.create!(
      pipeline: pipeline, trigger_stage: stage,
      name: 'Test Auto', conditions: {}
    )
  end
  let(:action) do
    KanbanAutomationAction.create!(
      kanban_automation: automation,
      action_type: 'send_whatsapp',
      delay_type: 'minutes',
      delay_minutes: 0,
      position: 0,
      config: { 'use_ai' => true, 'ai_prompt' => '' }
    )
  end
  let(:execution) do
    KanbanAutomationExecution.create!(
      kanban_automation_action: action,
      kanban_item: item,
      scheduled_at: Time.current,
      status: 'pending'
    )
  end

  let(:ai_agent) do
    AiAgent.create!(
      account: account,
      name: 'Assistente IA',
      language: 'pt',
      active: true,
      llm_provider: 'openai',
      llm_model: 'gpt-4o-mini',
      llm_api_key_encrypted: 'test-key'
    )
  end

  let(:llm_response) do
    AiAgent::LlmService::LlmResponse.new(type: :text, text: 'Olá! Estamos à disposição.', tool_calls: [], raw_parts: nil)
  end

  def build_service
    described_class.new(execution)
  end

  describe '#generate_ai_message (via #perform → execute_send_whatsapp)' do
    subject(:service) { build_service }

    context 'quando conta não tem agente IA ativo' do
      it 'raise com mensagem descritiva' do
        expect { service.send(:generate_ai_message) }
          .to raise_error(RuntimeError, /não tem agente IA ativo/)
      end
    end

    context 'quando conta tem agente IA ativo' do
      before { ai_agent }

      context 'com conversa vazia (sem mensagens)' do
        it 'chama LlmService com messages_history vazio e retorna texto do LLM' do
          allow(AiAgent::LlmService).to receive(:call).and_return(llm_response)
          result = service.send(:generate_ai_message)
          expect(result).to eq('Olá! Estamos à disposição.')
          expect(AiAgent::LlmService).to have_received(:call) do |_agent, prompt, **|
            expect(prompt[:messages]).to eq([])
          end
        end
      end

      context 'com conversa com 5 mensagens' do
        before do
          3.times { |i| create(:message, conversation: conversation, message_type: :incoming, content: "msg incoming #{i}") }
          2.times { |i| create(:message, conversation: conversation, message_type: :outgoing, content: "msg outgoing #{i}") }
        end

        it 'envia todas as 5 mensagens no histórico' do
          allow(AiAgent::LlmService).to receive(:call).and_return(llm_response)
          service.send(:generate_ai_message)
          expect(AiAgent::LlmService).to have_received(:call) do |_agent, prompt, **|
            expect(prompt[:messages].length).to eq(5)
          end
        end
      end

      context 'com conversa com 50 mensagens' do
        before do
          50.times { |i| create(:message, conversation: conversation, message_type: :incoming, content: "msg #{i}") }
        end

        it 'limita o histórico a 20 mensagens' do
          allow(AiAgent::LlmService).to receive(:call).and_return(llm_response)
          service.send(:generate_ai_message)
          expect(AiAgent::LlmService).to have_received(:call) do |_agent, prompt, **|
            expect(prompt[:messages].length).to eq(20)
          end
        end
      end

      context 'com notas privadas na conversa' do
        before do
          create(:message, conversation: conversation, message_type: :outgoing, content: 'msg pública', private: false)
          create(:message, conversation: conversation, message_type: :outgoing, content: 'nota privada', private: true)
        end

        it 'exclui notas privadas do histórico' do
          allow(AiAgent::LlmService).to receive(:call).and_return(llm_response)
          service.send(:generate_ai_message)
          expect(AiAgent::LlmService).to have_received(:call) do |_agent, prompt, **|
            contents = prompt[:messages].map { |m| m[:content] }
            expect(contents).to include('msg pública')
            expect(contents).not_to include('nota privada')
          end
        end
      end

      context 'com ai_prompt vazio' do
        it 'não inclui bloco INTENÇÃO DO OPERADOR no system prompt' do
          allow(AiAgent::LlmService).to receive(:call).and_return(llm_response)
          service.send(:generate_ai_message)
          expect(AiAgent::LlmService).to have_received(:call) do |_agent, prompt, **|
            expect(prompt[:system]).not_to include('INTENÇÃO DO OPERADOR')
          end
        end
      end

      context 'com ai_prompt preenchido' do
        before { action.update!(config: { 'use_ai' => true, 'ai_prompt' => 'lembrar do desconto de 20%' }) }

        it 'inclui INTENÇÃO DO OPERADOR no system prompt' do
          allow(AiAgent::LlmService).to receive(:call).and_return(llm_response)
          service.send(:generate_ai_message)
          expect(AiAgent::LlmService).to have_received(:call) do |_agent, prompt, **|
            expect(prompt[:system]).to include('INTENÇÃO DO OPERADOR')
            expect(prompt[:system]).to include('lembrar do desconto de 20%')
          end
        end
      end

      context 'quando LLM retorna texto vazio' do
        let(:empty_response) do
          AiAgent::LlmService::LlmResponse.new(type: :text, text: '', tool_calls: [], raw_parts: nil)
        end

        it 'raise com mensagem descritiva' do
          allow(AiAgent::LlmService).to receive(:call).and_return(empty_response)
          expect { service.send(:generate_ai_message) }
            .to raise_error(RuntimeError, /mensagem vazia/)
        end
      end

      context 'quando LLM retorna texto maior que 4000 chars' do
        let(:long_response) do
          AiAgent::LlmService::LlmResponse.new(type: :text, text: 'x' * 5000, tool_calls: [], raw_parts: nil)
        end

        it 'trunca em 4000 caracteres' do
          allow(AiAgent::LlmService).to receive(:call).and_return(long_response)
          result = service.send(:generate_ai_message)
          expect(result.length).to eq(4000)
        end
      end
    end
  end

  describe 'smoke regression: use_ai=false continua funcionando' do
    let(:fixed_action) do
      KanbanAutomationAction.create!(
        kanban_automation: automation,
        action_type: 'send_whatsapp',
        delay_type: 'minutes',
        delay_minutes: 0,
        position: 0,
        config: { 'use_ai' => false, 'message' => 'Mensagem fixa de teste' }
      )
    end
    let(:fixed_execution) do
      KanbanAutomationExecution.create!(
        kanban_automation_action: fixed_action,
        kanban_item: item,
        scheduled_at: Time.current,
        status: 'pending'
      )
    end

    it 'não invoca generate_ai_message quando use_ai=false' do
      service = described_class.new(fixed_execution)
      expect(service).not_to receive(:generate_ai_message)
      allow(service).to receive(:execute_send_whatsapp)
      service.perform
    end
  end
end

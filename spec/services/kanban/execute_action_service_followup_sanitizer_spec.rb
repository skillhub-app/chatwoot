# frozen_string_literal: true

require 'rails_helper'

# Sprint v66 — Fix A integrado. A saída do LLM no follow-up do Kanban DEVE passar
# pelo AiAgent::FollowUpOutputSanitizer antes de virar mensagem ao lead, para que
# nenhum scaffold do prompt (ex.: "Sua tarefa:", "(Aguardando resposta...)") vaze
# para o WhatsApp. Bug confirmado nas conversas 676 (Sol) e 644.
RSpec.describe Kanban::ExecuteActionService, 'follow-up output sanitization (v66)' do
  let(:account)      { create(:account) }
  let(:contact)      { create(:contact, account: account, phone_number: '+5551999502911', name: 'Sol') }
  let(:inbox)        { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, status: :open) }
  let(:pipeline)     { KanbanPipeline.create!(account: account, name: 'Vendas', position: 0, visibility_type: 'all') }
  let(:stage)        { KanbanStage.create!(pipeline: pipeline, name: 'Proposta', position: 0, probability: 50) }
  let(:item) do
    KanbanItem.create!(
      account: account, pipeline: pipeline, stage: stage, title: 'Lead Sol', position: 0,
      contact: contact, contact_phone: contact.phone_number, conversation: conversation
    )
  end
  let(:automation) do
    KanbanAutomation.create!(pipeline: pipeline, trigger_stage: stage, name: 'FollowUp', conditions: {})
  end
  let(:action) do
    KanbanAutomationAction.create!(
      kanban_automation: automation, action_type: 'send_whatsapp',
      delay_type: 'minutes', delay_minutes: 0, position: 0,
      config: { 'use_ai' => true, 'ai_prompt' => 'Oi, tudo bem?' }
    )
  end
  let(:execution) do
    KanbanAutomationExecution.create!(
      kanban_automation_action: action, kanban_item: item,
      scheduled_at: Time.current, status: 'pending'
    )
  end
  let!(:ai_agent) do
    AiAgent.create!(
      account: account, name: 'Julia', company: 'Volponi e Oliveira', language: 'pt',
      active: true, llm_provider: 'gemini', llm_model: 'gemini-3.1-flash-lite',
      llm_api_key_encrypted: 'test-key'
    )
  end

  subject(:service) { described_class.new(execution) }

  def stub_llm(text)
    resp = AiAgent::LlmService::LlmResponse.new(type: :text, text: text, tool_calls: [], raw_parts: nil)
    allow(AiAgent::LlmService).to receive(:call).and_return(resp)
  end

  it 'sanitiza o scaffold ecoado (string real da conv 676) antes de retornar' do
    stub_llm("(Aguardando resposta da cliente)\n\n---\n*Sua tarefa: gerar o follow-up*\n\nOi, Sol! Está por aí?")
    result = service.send(:generate_ai_message)
    expect(result).to eq('Oi, Sol! Está por aí?')
    expect(result).not_to match(/sua tarefa/i)
    expect(result).not_to match(/aguardando/i)
  end

  it 'não altera uma mensagem já limpa do LLM (regressão)' do
    clean = 'Oi, Sol! Passando para saber se você viu minha última mensagem.'
    stub_llm(clean)
    expect(service.send(:generate_ai_message)).to eq(clean)
  end

  it 'passa a saída crua do LLM pelo sanitizer' do
    stub_llm('Oi, tudo certo?')
    allow(AiAgent::FollowUpOutputSanitizer).to receive(:call).and_call_original
    service.send(:generate_ai_message)
    expect(AiAgent::FollowUpOutputSanitizer).to have_received(:call).with('Oi, tudo certo?')
  end

  it 'levanta erro se a resposta for puramente scaffold (vazia após sanitização)' do
    stub_llm("## Sua tarefa:\n---")
    expect { service.send(:generate_ai_message) }.to raise_error(RuntimeError, /vazia/)
  end
end

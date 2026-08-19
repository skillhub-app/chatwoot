require 'rails_helper'

RSpec.describe AiAgent::ProcessMessageJob do
  let(:account)      { create(:account) }
  let(:inbox)        { create(:inbox, account: account) }
  let(:contact)      { create(:contact, account: account) }
  let(:agent)        { create(:ai_agent, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:messages)     { ['oi, tudo bem?'] }

  before do
    buffer_double = instance_double(AiAgent::MessageBuffer)
    allow(AiAgent::MessageBuffer).to receive(:new).and_return(buffer_double)
    allow(buffer_double).to receive(:pop_all).and_return(messages)
    allow(buffer_double).to receive(:release_lock)

    allow(AiAgent::PromptBuilder).to receive(:build).and_raise(
      StandardError, 'Gemini error: {"error"=>{"code"=>503, "status"=>"UNAVAILABLE"}}'
    )
  end

  describe 'quando o processamento estoura uma exceção não recuperável (bug A+B)' do
    it 'não propaga a exceção pra fora do job (Sidekiq não fica reagendando um buffer já vazio)' do
      expect { described_class.new.perform(agent.id, conversation.id) }.not_to raise_error
    end

    it 'envia a FALLBACK_MESSAGE pro lead' do
      expect(AiAgent::MessageHumanizer).to receive(:send_response).with(
        conversation,
        described_class::FALLBACK_MESSAGE,
        agent: agent,
        last_was_audio: false
      )
      described_class.new.perform(agent.id, conversation.id)
    end

    it 'cria activity message avisando do erro' do
      expect(AiAgent::ActivityService).to receive(:ai_error).with(conversation)
      described_class.new.perform(agent.id, conversation.id)
    end

    it 'adiciona a label ia-com-erro na conversa' do
      described_class.new.perform(agent.id, conversation.id)
      expect(conversation.reload.label_list).to include('ia-com-erro')
    end

    it 'não duplica a label se já estiver presente' do
      conversation.update!(label_list: ['ia-com-erro'])
      described_class.new.perform(agent.id, conversation.id)
      expect(conversation.reload.label_list.count('ia-com-erro')).to eq(1)
    end

    it 'registra a execution com status error' do
      expect { described_class.new.perform(agent.id, conversation.id) }
        .to change(AiAgentExecution, :count).by(1)
      expect(AiAgentExecution.last.status).to eq('error')
    end

    it 'uma falha ao notificar (ex: MessageHumanizer também explode) não derruba o job' do
      allow(AiAgent::MessageHumanizer).to receive(:send_response).and_raise(StandardError, 'send falhou também')
      expect { described_class.new.perform(agent.id, conversation.id) }.not_to raise_error
    end
  end

  describe 'regressão: fluxo normal (sem erro) continua enviando resposta e sem overhead' do
    let(:llm_response) do
      AiAgent::LlmService::LlmResponse.new(type: :text, text: 'Olá! Como posso ajudar?', tool_calls: [], raw_parts: nil)
    end

    before do
      allow(AiAgent::PromptBuilder).to receive(:build).and_call_original
      allow(AiAgent::LlmService).to receive(:call).and_return(llm_response)
    end

    it 'não aciona FALLBACK_MESSAGE nem a label de erro' do
      expect(AiAgent::MessageHumanizer).to receive(:send_response).with(
        conversation, 'Olá! Como posso ajudar?', agent: agent, last_was_audio: false
      )
      described_class.new.perform(agent.id, conversation.id)
      expect(conversation.reload.label_list).not_to include('ia-com-erro')
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiAgent::ProtocolExecutor do
  let(:account)      { create(:account) }
  let(:inbox)        { create(:inbox, account: account) }
  let(:user)         { create(:user, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:agent) do
    AiAgent.create!(
      account: account, name: 'Clara', language: 'pt', active: true,
      llm_provider: 'openai', llm_model: 'gpt-4o-mini',
      llm_api_key_encrypted: 'test-key'
    )
  end
  let(:protocol) do
    AiAgentProtocol.create!(
      ai_agent: agent, protocol_type: 'human', label: 'Humano',
      keyword: '#HUMANO', auto_summarize: true, position: 0
    )
  end
  let(:pipeline) do
    KanbanPipeline.create!(account: account, name: 'Vendas', position: 0, visibility_type: 'all')
  end
  let(:stage) do
    KanbanStage.create!(pipeline: pipeline, name: 'Proposta', position: 0, probability: 50)
  end

  before { create(:account_user, account: account, user: user) }

  describe '#send_summary (via execute)' do
    context 'com kanban_item vinculado à conversa' do
      let!(:kanban_item) do
        KanbanItem.create!(
          account: account, pipeline: pipeline, stage: stage,
          title: 'Lead Teste', position: 0, conversation: conversation
        )
      end

      it 'cria KanbanNote no card vinculado' do
        expect {
          described_class.execute(protocol, conversation, agent, summary_text: 'Resumo do atendimento.')
        }.to change { kanban_item.kanban_notes.count }.by(1)
      end

      it 'KanbanNote contém o texto do resumo' do
        described_class.execute(protocol, conversation, agent, summary_text: 'Resumo do atendimento.')
        note = kanban_item.kanban_notes.last
        expect(note.content).to include('Resumo do atendimento.')
      end
    end

    context 'sem kanban_item vinculado' do
      it 'não levanta erro e não tenta criar KanbanNote' do
        expect {
          described_class.execute(protocol, conversation, agent, summary_text: 'Resumo.')
        }.not_to raise_error
        expect(KanbanNote.count).to eq(0)
      end
    end

    context 'com summary_text nil' do
      it 'não cria private note nem KanbanNote' do
        expect {
          described_class.execute(protocol, conversation, agent, summary_text: nil)
        }.not_to change { conversation.messages.where(private: true).count }
        expect(KanbanNote.count).to eq(0)
      end
    end

    context 'quando criação de KanbanNote falha' do
      let!(:kanban_item) do
        KanbanItem.create!(
          account: account, pipeline: pipeline, stage: stage,
          title: 'Lead Teste', position: 0, conversation: conversation
        )
      end

      it 'não impede a criação da private note na conversa' do
        allow_any_instance_of(KanbanNote).to receive(:save!).and_raise(StandardError, 'DB error')
        expect(Rails.logger).to receive(:error).with(/ProtocolExecutor.*DB error/)

        expect {
          described_class.execute(protocol, conversation, agent, summary_text: 'Resumo.')
        }.to change { conversation.messages.where(private: true).count }.by(1)
      end
    end
  end
end

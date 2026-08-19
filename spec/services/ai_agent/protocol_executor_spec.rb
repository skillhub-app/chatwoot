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

  let(:ai_conv) do
    AiAgentConversation.create!(
      ai_agent: agent, conversation: conversation,
      contact: conversation.contact, state: 'active'
    )
  end

  describe '#apply_action (via execute)' do
    context "action='continue'" do
      let(:protocol) do
        AiAgentProtocol.create!(
          ai_agent: agent, protocol_type: 'qualified', label: 'Qualificado',
          keyword: '#QUALIFICADO', auto_summarize: false, position: 0, action: 'continue'
        )
      end

      before { ai_conv }

      it 'não altera state da ai_agent_conversation' do
        expect { described_class.execute(protocol, conversation, agent) }
          .not_to(change { ai_conv.reload.state })
      end

      it 'gera resumo quando auto_summarize=true' do
        protocol.update!(auto_summarize: true)
        expect {
          described_class.execute(protocol, conversation, agent, summary_text: 'Resumo.')
        }.to change { conversation.messages.where(private: true).count }.by(1)
      end

      it 'envia notificação UAZAPI quando phone_number presente' do
        protocol.update!(phone_number: '+5511999990000', auto_summarize: false)
        allow(AiAgent::ProtocolNotificationService).to receive(:call)
        described_class.execute(protocol, conversation, agent, summary_text: 'Resumo.')
        expect(AiAgent::ProtocolNotificationService).to have_received(:call)
      end
    end

    context "action='pause_for_human'" do
      let(:protocol) do
        AiAgentProtocol.create!(
          ai_agent: agent, protocol_type: 'human', label: 'Humano',
          keyword: '#HUMANO', auto_summarize: false, position: 0, action: 'pause_for_human'
        )
      end

      before { ai_conv }

      it "muda state para 'transferred'" do
        described_class.execute(protocol, conversation, agent)
        expect(ai_conv.reload.state).to eq('transferred')
      end

      it 'grava paused_reason com tipo do protocolo' do
        described_class.execute(protocol, conversation, agent)
        expect(ai_conv.reload.paused_reason).to eq('protocol:human')
      end

      it 'remove ia_ligada e adiciona ia_desligada' do
        conversation.labels.push('ia_ligada')
        described_class.execute(protocol, conversation, agent)
        expect(conversation.reload.label_list).to include('ia_desligada')
        expect(conversation.reload.label_list).not_to include('ia_ligada')
      end
    end

    context "action='end_conversation'" do
      let(:protocol) do
        AiAgentProtocol.create!(
          ai_agent: agent, protocol_type: 'unqualified', label: 'Desqualificado',
          keyword: '#DESQ', auto_summarize: false, position: 0, action: 'end_conversation'
        )
      end

      before { ai_conv }

      it "muda state para 'ended'" do
        described_class.execute(protocol, conversation, agent)
        expect(ai_conv.reload.state).to eq('ended')
      end

      it 'adiciona etiqueta atendimento_encerrado' do
        described_class.execute(protocol, conversation, agent)
        expect(conversation.reload.label_list).to include('atendimento_encerrado')
      end

      it 'adiciona ia_desligada' do
        described_class.execute(protocol, conversation, agent)
        expect(conversation.reload.label_list).to include('ia_desligada')
      end
    end

    context "action='pause_temporary'" do
      let(:protocol) do
        AiAgentProtocol.create!(
          ai_agent: agent, protocol_type: 'custom', label: 'Temp',
          keyword: '#TEMP', auto_summarize: false, position: 0, action: 'pause_temporary'
        )
      end

      before { ai_conv }

      it "muda state para 'paused'" do
        described_class.execute(protocol, conversation, agent)
        expect(ai_conv.reload.state).to eq('paused')
      end
    end

    context 'default action em protocolo recém-criado' do
      it "é 'pause_for_human'" do
        p = AiAgentProtocol.create!(
          ai_agent: agent, protocol_type: 'human', label: 'H',
          keyword: '#H', auto_summarize: false, position: 0
        )
        expect(p.action).to eq('pause_for_human')
      end
    end

    context 'sem ai_agent_conversation existente' do
      it 'não levanta erro' do
        expect {
          described_class.execute(protocol, conversation, agent)
        }.not_to raise_error
      end
    end
  end

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

  describe '#notify_phone (via execute)' do
    let(:protocol_with_phone) do
      AiAgentProtocol.create!(
        ai_agent: agent, protocol_type: 'human', label: 'Humano',
        keyword: '#HUMANO', auto_summarize: true, position: 0,
        phone_number: '+5511999990000'
      )
    end

    context 'com phone_number e summary_text presentes' do
      it 'chama ProtocolNotificationService' do
        expect(AiAgent::ProtocolNotificationService).to receive(:call).with(
          phone:   '+5511999990000',
          summary: 'Resumo.',
          account: conversation.account
        )
        described_class.execute(protocol_with_phone, conversation, agent, summary_text: 'Resumo.')
      end
    end

    context 'com summary_text nil' do
      it 'não chama ProtocolNotificationService' do
        expect(AiAgent::ProtocolNotificationService).not_to receive(:call)
        described_class.execute(protocol_with_phone, conversation, agent, summary_text: nil)
      end
    end

    context 'sem phone_number no protocolo' do
      it 'não chama ProtocolNotificationService' do
        expect(AiAgent::ProtocolNotificationService).not_to receive(:call)
        described_class.execute(protocol, conversation, agent, summary_text: 'Resumo.')
      end
    end

    context 'ProtocolNotificationService levanta exceção' do
      it 'não propaga o erro' do
        allow(AiAgent::ProtocolNotificationService).to receive(:call).and_raise(StandardError, 'network error')
        expect {
          described_class.execute(protocol_with_phone, conversation, agent, summary_text: 'Resumo.')
        }.not_to raise_error
      end
    end
  end
end

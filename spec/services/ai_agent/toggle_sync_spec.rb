require 'rails_helper'

# FIX 1 (v64): o toggle de IA por conversa tem o ai_agent_conversation.state como
# ÚNICA fonte de verdade. Estes specs garantem que (a) os portões decidem por state
# e (b) state e labels nunca dessincronizam quando um humano responde.
RSpec.describe 'AI toggle state/label sync', type: :model do
  let(:account)      { create(:account) }
  let(:inbox)        { create(:inbox, account: account) }
  let!(:agent)       { create(:ai_agent, account: account, inbox: inbox, active: true) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  def incoming!(content = 'oi')
    create(:message, account: account, conversation: conversation, inbox: inbox,
                     message_type: :incoming, content: content)
  end

  def human_reply!(content = 'oi, sou humano')
    create(:message, account: account, conversation: conversation, inbox: inbox,
                     message_type: :outgoing, sender: create(:user, account: account), content: content)
  end

  describe 'portão único = state (IncomingMessageProcessor + ProcessMessageJob)' do
    before { allow(AiAgent::ProcessMessageJob).to receive(:set).and_return(double(perform_later: true)) }

    it 'state=active → enfileira o processamento' do
      AiAgentConversation.create!(ai_agent: agent, conversation: conversation, state: 'active')
      incoming!
      expect(AiAgent::ProcessMessageJob).to have_received(:set)
    end

    it 'state=paused → NÃO processa (mesmo sem a label) — regressão do dessync' do
      AiAgentConversation.create!(ai_agent: agent, conversation: conversation, state: 'paused')
      incoming!
      expect(AiAgent::ProcessMessageJob).not_to have_received(:set)
    end
  end

  describe 'pause_ai_on_human_response sincroniza state E labels' do
    it 'humano responde → state=paused + label ia_desligada' do
      ai_conv = AiAgentConversation.create!(ai_agent: agent, conversation: conversation, state: 'active')

      human_reply!

      expect(ai_conv.reload.state).to eq('paused')
      expect(conversation.reload.label_list).to include('ia_desligada')
      expect(conversation.label_list).not_to include('ia_ligada')
    end

    it 'comando de reativação → state=active + label ia_ligada' do
      agent.update!(reactivation_command: '#ligaia')
      ai_conv = AiAgentConversation.create!(ai_agent: agent, conversation: conversation, state: 'paused')

      human_reply!('#ligaia pode seguir')

      expect(ai_conv.reload.state).to eq('active')
      expect(conversation.reload.label_list).to include('ia_ligada')
      expect(conversation.label_list).not_to include('ia_desligada')
    end
  end

  describe 'REGRESSÃO: áudio continua sendo injetado no conteúdo' do
    it 'extract_message_content mantém o [Áudio]: <transcrição>' do
      msg = incoming!('')
      att = msg.attachments.create!(account_id: account.id, file_type: :audio)
      att.file.attach(io: Rails.root.join('spec/assets/sample.mp3').open, filename: 'a.mp3', content_type: 'audio/mp3')
      att.update!(meta: { 'transcribed_text' => 'quero saber o preço' })

      content = AiAgent::IncomingMessageProcessor.new(msg.reload).send(:extract_message_content, msg)
      expect(content).to include('[Áudio]: quero saber o preço')
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

# Sprint v68 — fix da race condition no envio de áudio.
# Antes: messages.create! commitava e o after_create_commit enfileirava o
# SendReplyJob ANTES do anexo ser persistido (~2-50ms depois) → o
# WhatsappCloudService montava text.body: nil → Meta HTTP 400.
# Agora: mensagem + anexo numa única transação; o after_create_commit só
# dispara após o COMMIT final, com o áudio já presente.
RSpec.describe AiAgent::MessageHumanizer do
  let(:account)      { create(:account) }
  let(:inbox)        { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  before { allow(AiAgent::IncomingMessageProcessor).to receive(:call) }

  let(:tts_agent) do
    double(
      'AiAgent',
      tts_enabled?:          true,
      tts_voice_id:          'voice123',
      tts_api_key_encrypted: 'sk-test',
      message_chunk_size:    300
    )
  end

  describe 'atomicidade mensagem + anexo (v68)' do
    before { allow(AiAgent::TtsService).to receive(:convert).and_return('mp3bytes') }

    def run_audio
      described_class.send_response(conversation, 'Olá!', agent: tts_agent, last_was_audio: true)
    end

    it 'cria a mensagem outgoing JÁ com o anexo de áudio e content nil' do
      run_audio

      message = conversation.messages.outgoing.last
      expect(message.content).to be_nil
      expect(message.attachments.count).to eq(1)
      expect(message.attachments.first.file_type).to eq('audio')
    end

    it 'um find fresco (como o SendReplyJob faz) já enxerga o anexo' do
      run_audio

      message_id = conversation.messages.outgoing.last.id
      expect(Message.find(message_id).attachments).to be_present
    end

    it 'nunca deixa uma mensagem de áudio sem anexo (invariante anti-race)' do
      run_audio

      audio_messages = conversation.messages.outgoing.where(content: nil)
      expect(audio_messages).to be_present
      audio_messages.each { |m| expect(m.attachments).to be_present }
    end
  end

  describe 'rollback quando o anexo falha (v68)' do
    before { allow(AiAgent::TtsService).to receive(:convert).and_return('mp3bytes') }

    it 'faz rollback da mensagem (sem outgoing órfã) e retorna false' do
      humanizer = described_class.new(conversation, 'Olá!', agent: tts_agent, last_was_audio: true)
      allow(humanizer).to receive(:attach_audio!).and_raise(StandardError, 'attach failed')

      expect(humanizer.send(:send_audio)).to be(false)
      expect(conversation.messages.outgoing.count).to eq(0)
    end
  end
end

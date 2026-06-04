# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiAgent::MessageHumanizer do
  let(:account)      { create(:account) }
  let(:inbox)        { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  # Prevent after_create_commit callbacks from triggering the AI processor
  before { allow(AiAgent::IncomingMessageProcessor).to receive(:call) }

  # Agent double with TTS fully configured
  let(:tts_agent) do
    double(
      'AiAgent',
      tts_enabled?:          true,
      tts_voice_id:          'voice123',
      tts_api_key_encrypted: 'sk-test',
      message_chunk_size:    300
    )
  end

  # Agent double with TTS disabled
  let(:no_tts_agent) do
    double('AiAgent', tts_enabled?: false, message_chunk_size: 300)
  end

  describe '#send_response' do
    context 'last_was_audio=true + TTS totalmente configurado' do
      it 'envia áudio e NÃO envia texto' do
        allow(AiAgent::TtsService).to receive(:convert).and_return('mp3bytes')

        expect(AiAgent::TtsService).to receive(:convert).once

        # should NOT create any text messages via send_chunk
        humanizer = described_class.new(conversation, 'Olá!',
                                        agent: tts_agent, last_was_audio: true)
        expect(humanizer).not_to receive(:send_chunk)
        humanizer.send_response
      end
    end

    context 'last_was_audio=false + TTS habilitado' do
      it 'envia texto e NÃO chama TtsService' do
        expect(AiAgent::TtsService).not_to receive(:convert)

        described_class.send_response(
          conversation, 'Resposta em texto',
          agent: tts_agent, last_was_audio: false
        )

        expect(conversation.messages.outgoing.count).to eq(1)
        expect(conversation.messages.outgoing.last.content).to eq('Resposta em texto')
      end
    end

    context 'last_was_audio=true + tts_enabled=false' do
      it 'envia texto (TTS desligado)' do
        expect(AiAgent::TtsService).not_to receive(:convert)

        described_class.send_response(
          conversation, 'Texto normal',
          agent: no_tts_agent, last_was_audio: true
        )

        expect(conversation.messages.outgoing.last.content).to eq('Texto normal')
      end
    end

    context 'last_was_audio=true + voice_id ausente' do
      let(:agent_sem_voice) do
        double('AiAgent', tts_enabled?: true, tts_voice_id: '',
                          tts_api_key_encrypted: 'sk-test', message_chunk_size: 300)
      end

      it 'envia texto (faltam dados TTS)' do
        expect(AiAgent::TtsService).not_to receive(:convert)

        described_class.send_response(
          conversation, 'Texto por falta de voice_id',
          agent: agent_sem_voice, last_was_audio: true
        )

        expect(conversation.messages.outgoing.last.content).to eq('Texto por falta de voice_id')
      end
    end

    context 'last_was_audio=true + TtsService retorna nil (fallback)' do
      it 'envia texto como fallback quando TTS falha' do
        allow(AiAgent::TtsService).to receive(:convert).and_return(nil)

        described_class.send_response(
          conversation, 'Fallback texto',
          agent: tts_agent, last_was_audio: true
        )

        expect(conversation.messages.outgoing.last.content).to eq('Fallback texto')
      end
    end
  end
end

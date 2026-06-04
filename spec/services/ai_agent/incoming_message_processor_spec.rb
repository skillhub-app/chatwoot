# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiAgent::IncomingMessageProcessor do
  let(:account)      { create(:account) }
  let(:inbox)        { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  # Prevent the after_create_commit callback from triggering a nested processor
  # on messages that have non-blank content (which would run deeper DB queries
  # and abort the test transaction before our assertion runs).
  before { allow(described_class).to receive(:call) }

  describe '#audio_pending_transcription?' do
    subject(:processor) { described_class.new(message) }

    # Specs 1-4 override account so the feature is enabled.
    # We must also pass account: explicitly to the message factory because the
    # default message factory creates its own account (ignoring the conversation's).
    context 'account com audio_transcriptions ativo + áudio SEM transcrição' do
      let(:account) { create(:account, audio_transcriptions: true) }
      let(:message) do
        create(:message, account: account, conversation: conversation,
                         message_type: :incoming, content: '[audio]')
      end

      before { message.attachments.create!(account_id: account.id, file_type: :audio) }

      it 'retorna true (bloqueia — espera Whisper)' do
        expect(processor.send(:audio_pending_transcription?)).to eq(true)
      end
    end

    context 'account com audio_transcriptions ativo + áudio COM transcrição' do
      let(:account) { create(:account, audio_transcriptions: true) }
      let(:message) do
        create(:message, account: account, conversation: conversation,
                         message_type: :incoming, content: '[audio]')
      end

      before do
        message.attachments.create!(
          account_id: account.id, file_type: :audio,
          meta: { 'transcribed_text' => 'Oi, tudo bem?' }
        )
      end

      it 'retorna false (permite processamento)' do
        expect(processor.send(:audio_pending_transcription?)).to eq(false)
      end
    end

    context 'texto + áudio SEM transcrição + feature ativa' do
      let(:account) { create(:account, audio_transcriptions: true) }
      let(:message) do
        create(:message, account: account, conversation: conversation,
                         message_type: :incoming, content: 'Segue:')
      end

      before { message.attachments.create!(account_id: account.id, file_type: :audio) }

      it 'retorna true (espera Whisper mesmo tendo texto)' do
        expect(processor.send(:audio_pending_transcription?)).to eq(true)
      end
    end

    context 'texto + áudio COM transcrição + feature ativa' do
      let(:account) { create(:account, audio_transcriptions: true) }
      let(:message) do
        create(:message, account: account, conversation: conversation,
                         message_type: :incoming, content: 'Segue:')
      end

      before do
        message.attachments.create!(
          account_id: account.id, file_type: :audio,
          meta: { 'transcribed_text' => 'Preciso de ajuda' }
        )
      end

      it 'retorna false e message_content combina texto e transcrição' do
        expect(processor.send(:audio_pending_transcription?)).to eq(false)
        expect(processor.send(:message_content)).to eq("Segue:\n\n[Áudio]: Preciso de ajuda")
      end
    end

    context 'feature audio_transcriptions desativada (nil) + áudio sem transcrição' do
      # default account has audio_transcriptions = nil — feature off
      let(:message) do
        create(:message, account: account, conversation: conversation,
                         message_type: :incoming, content: '[audio]')
      end

      before { message.attachments.create!(account_id: account.id, file_type: :audio) }

      it 'retorna false (comportamento legado — não bloqueia)' do
        expect(processor.send(:audio_pending_transcription?)).to eq(false)
      end
    end
  end

  describe '#message_content' do
    subject(:processor) { described_class.new(message) }

    context 'texto puro' do
      let(:message) do
        create(:message, conversation: conversation, message_type: :incoming, content: 'Olá, tudo bem?')
      end

      it 'retorna o content da mensagem' do
        expect(processor.send(:message_content)).to eq('Olá, tudo bem?')
      end
    end

    context 'áudio com transcrição' do
      let(:message) do
        create(:message, conversation: conversation, message_type: :incoming, content: nil)
      end

      before do
        message.attachments.create!(
          account_id: account.id,
          file_type:  :audio,
          meta:       { 'transcribed_text' => 'Quero saber o preço do plano' }
        )
      end

      it 'retorna "[Áudio]: <transcrição>"' do
        expect(processor.send(:message_content)).to eq('[Áudio]: Quero saber o preço do plano')
      end
    end

    context 'áudio SEM transcrição (meta vazio)' do
      let(:message) do
        create(:message, conversation: conversation, message_type: :incoming, content: nil)
      end

      before do
        message.attachments.create!(account_id: account.id, file_type: :audio)
      end

      it 'retorna string vazia' do
        expect(processor.send(:message_content)).to eq('')
      end
    end

    context 'texto + áudio com transcrição' do
      let(:message) do
        create(:message, conversation: conversation, message_type: :incoming, content: 'Segue o áudio:')
      end

      before do
        message.attachments.create!(
          account_id: account.id,
          file_type:  :audio,
          meta:       { 'transcribed_text' => 'Preciso de ajuda com o contrato' }
        )
      end

      it 'combina texto e transcrição separados por linha em branco' do
        expect(processor.send(:message_content)).to eq("Segue o áudio:\n\n[Áudio]: Preciso de ajuda com o contrato")
      end
    end
  end
end

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

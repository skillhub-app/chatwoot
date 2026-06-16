# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiAgent::PromptBuilder do
  let(:account)      { create(:account) }
  let(:inbox)        { create(:inbox, account: account) }
  let(:contact)      { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  # Use a plain double to avoid requiring the ai_agents table (custom migration, not in base schema.rb).
  # memory_window_messages comes from store_accessor so instance_double won't see it.
  let(:agent)        { double('AiAgent', memory_window_messages: 100) }

  subject(:builder) { described_class.new(agent, conversation, []) }

  # Prevent after_create_commit from triggering the processor on incoming messages
  before { allow(AiAgent::IncomingMessageProcessor).to receive(:call) }

  describe '#extract_message_content_for_history (áudio)' do
    context 'incoming com áudio transcrito' do
      let(:msg) { create(:message, conversation: conversation, message_type: :incoming, content: nil) }

      before do
        msg.attachments.create!(account_id: account.id, file_type: :audio,
                                meta: { 'transcribed_text' => 'Quero saber o preço do plano' })
      end

      it 'retorna prefixo [Áudio]: para mensagem de entrada' do
        result = builder.send(:extract_message_content_for_history, msg.reload)
        expect(result).to eq('[Áudio]: Quero saber o preço do plano')
      end
    end

    context 'outgoing (AI TTS) com áudio transcrito limpo' do
      let(:msg) { create(:message, conversation: conversation, message_type: :outgoing, content: nil) }

      before do
        msg.attachments.create!(account_id: account.id, file_type: :audio,
                                meta: { 'transcribed_text' => 'Olá, como posso ajudar?' })
      end

      it 'retorna texto SEM prefixo [Áudio]:' do
        result = builder.send(:extract_message_content_for_history, msg.reload)
        expect(result).to eq('Olá, como posso ajudar?')
        expect(result).not_to include('[Áudio]')
      end
    end

    context 'outgoing com artefato "Áudio. Áudio." herdado' do
      let(:msg) { create(:message, conversation: conversation, message_type: :outgoing, content: nil) }

      before do
        msg.attachments.create!(account_id: account.id, file_type: :audio,
                                meta: { 'transcribed_text' => 'Áudio. Áudio. Áudio. Olá, tudo bem?' })
      end

      it 'remove os artefatos "Áudio." do início e retorna só o conteúdo real' do
        result = builder.send(:extract_message_content_for_history, msg.reload)
        expect(result).to eq('Olá, tudo bem?')
      end
    end

    context 'outgoing TTS cujo transcribed_text NÃO começa com Áudio' do
      let(:msg) { create(:message, conversation: conversation, message_type: :outgoing, content: nil) }

      before do
        msg.attachments.create!(account_id: account.id, file_type: :audio,
                                meta: { 'transcribed_text' => 'Perfeito, vou verificar isso para você.' })
      end

      it 'retorna o texto diretamente sem modificação' do
        result = builder.send(:extract_message_content_for_history, msg.reload)
        expect(result).to eq('Perfeito, vou verificar isso para você.')
      end
    end

    context 'regressão: incoming de texto (sem áudio)' do
      let(:msg) { create(:message, conversation: conversation, message_type: :incoming, content: 'Olá!') }

      it 'retorna o conteúdo de texto normalmente' do
        result = builder.send(:extract_message_content_for_history, msg.reload)
        expect(result).to eq('Olá!')
      end
    end

    context 'regressão: outgoing de texto (sem áudio)' do
      let(:msg) { create(:message, conversation: conversation, message_type: :outgoing, content: 'Tudo bem!') }

      it 'retorna o conteúdo de texto normalmente' do
        result = builder.send(:extract_message_content_for_history, msg.reload)
        expect(result).to eq('Tudo bem!')
      end
    end
  end
end

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

  describe '#build_history_messages com áudio' do
    context 'mensagem de áudio com transcrição' do
      let(:audio_msg) do
        create(:message, conversation: conversation, message_type: :incoming, content: nil)
      end

      before do
        audio_msg.attachments.create!(
          account_id: account.id,
          file_type:  :audio,
          meta:       { 'transcribed_text' => 'Quero saber o preço do plano' }
        )
      end

      it 'inclui a mensagem no histórico com prefixo [Áudio]' do
        history = builder.send(:build_history_messages)
        expect(history).to include({ role: 'user', content: '[Áudio]: Quero saber o preço do plano' })
      end
    end

    context 'mensagem de áudio sem transcrição' do
      let(:audio_msg) do
        create(:message, conversation: conversation, message_type: :incoming, content: nil)
      end

      before do
        audio_msg.attachments.create!(account_id: account.id, file_type: :audio)
      end

      it 'exclui a mensagem de áudio sem transcrição do histórico' do
        history = builder.send(:build_history_messages)
        expect(history).to be_empty
      end
    end
  end
end

require 'rails_helper'

RSpec.describe AiAgent::ActivityService do
  let(:account)      { create(:account) }
  let(:conversation) { create(:conversation, account: account) }

  describe '.ai_enabled' do
    it 'enfileira ActivityMessageJob com "IA ativada por <user>"' do
      expect(Conversations::ActivityMessageJob).to receive(:perform_later) do |conv, params|
        expect(conv).to eq(conversation)
        expect(params[:message_type]).to eq(:activity)
        expect(params[:account_id]).to eq(conversation.account_id)
        expect(params[:content]).to eq('IA ativada por Maria')
      end
      described_class.ai_enabled(conversation, by: 'Maria')
    end

    it 'sem usuário usa "IA ativada"' do
      expect(Conversations::ActivityMessageJob).to receive(:perform_later)
        .with(conversation, hash_including(content: 'IA ativada'))
      described_class.ai_enabled(conversation)
    end
  end

  describe '.ai_disabled' do
    it 'enfileira "IA desativada por <user>"' do
      expect(Conversations::ActivityMessageJob).to receive(:perform_later)
        .with(conversation, hash_including(content: 'IA desativada por João'))
      described_class.ai_disabled(conversation, by: 'João')
    end
  end

  describe '.ai_auto_paused' do
    it 'enfileira "IA pausada automaticamente"' do
      expect(Conversations::ActivityMessageJob).to receive(:perform_later)
        .with(conversation, hash_including(content: 'IA pausada automaticamente (resposta humana)'))
      described_class.ai_auto_paused(conversation)
    end
  end

  describe 'graceful' do
    it 'não levanta se a conversa for nil' do
      expect { described_class.ai_enabled(nil) }.not_to raise_error
    end
  end
end

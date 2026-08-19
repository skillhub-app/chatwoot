# frozen_string_literal: true

require 'rails_helper'

# Sprint v68 — soft delete (scopes + helper). deleted_at preservado p/ auditoria.
RSpec.describe Message do
  let(:conversation) { create(:conversation) }
  let!(:visible_message) { create(:message, conversation: conversation, message_type: :outgoing) }
  let!(:deleted_message) do
    create(:message, conversation: conversation, message_type: :outgoing, deleted_at: Time.current)
  end

  describe 'scopes' do
    it '.visible exclui mensagens com deleted_at' do
      expect(described_class.visible).to include(visible_message)
      expect(described_class.visible).not_to include(deleted_message)
    end

    it '.soft_deleted retorna apenas mensagens com deleted_at' do
      expect(described_class.soft_deleted).to include(deleted_message)
      expect(described_class.soft_deleted).not_to include(visible_message)
    end
  end

  describe '#soft_deleted?' do
    it 'true quando deleted_at presente' do
      expect(deleted_message.soft_deleted?).to be true
    end

    it 'false quando deleted_at nil' do
      expect(visible_message.soft_deleted?).to be false
    end
  end

  describe 'default deleted_for_recipient' do
    it 'é false por padrão' do
      expect(visible_message.deleted_for_recipient).to be false
    end
  end
end

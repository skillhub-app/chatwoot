# frozen_string_literal: true

require 'rails_helper'

# Sprint v68 — matriz do destroy: soft delete + revoke Uazapi.
RSpec.describe 'Messages destroy (soft delete + Uazapi revoke) v68', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  before { create(:inbox_member, inbox: inbox, user: agent) }

  def delete_message(msg)
    delete "/api/v1/accounts/#{account.id}/conversations/#{msg.conversation.display_id}/messages/#{msg.id}",
           headers: agent.create_new_auth_token, as: :json
  end

  def stub_uazapi_channel
    allow_any_instance_of(Inbox).to receive(:channel_type).and_return('Channel::Uazapi') # rubocop:disable RSpec/AnyInstance
  end

  context 'mensagem incoming' do
    let(:message) do
      create(:message, message_type: :incoming, account: account, inbox: inbox, conversation: conversation, content: 'oi')
    end

    it 'retorna 403 e não apaga' do
      delete_message(message)
      expect(response).to have_http_status(:forbidden)
      expect(message.reload.deleted_at).to be_nil
    end
  end

  context 'outgoing não-whatsapp' do
    let(:message) do
      create(:message, message_type: :outgoing, account: account, inbox: inbox, conversation: conversation, content: 'Olá')
    end

    it 'soft delete local, deleted_for_recipient false, conteúdo preservado' do
      delete_message(message)
      expect(response).to have_http_status(:success)
      expect(message.reload.deleted_at).to be_present
      expect(message.reload.deleted_for_recipient).to be false
      expect(message.reload.content).to eq('Olá')
      expect(message.reload.content_attributes['deleted']).to be true
    end
  end

  context 'mensagem já apagada' do
    let(:message) do
      create(:message, message_type: :outgoing, account: account, inbox: inbox, conversation: conversation,
                       deleted_at: Time.current)
    end

    it 'retorna 422' do
      delete_message(message)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  context 'outgoing whatsapp (Uazapi) com source_id' do
    let(:message) do
      create(:message, message_type: :outgoing, account: account, inbox: inbox, conversation: conversation,
                       content: 'link', source_id: 'WAMSG1')
    end

    it 'revoke 200 → marca deleted_at + deleted_for_recipient true' do
      message
      stub_uazapi_channel
      allow(ChannelUazapi::RevokeMessageService).to receive(:new)
        .and_return(instance_double(ChannelUazapi::RevokeMessageService, perform: { success: true, code: 200 }))

      delete_message(message)
      expect(response).to have_http_status(:success)
      expect(message.reload.deleted_for_recipient).to be true
      expect(message.reload.deleted_at).to be_present
    end

    it 'revoke 500 → 422 e NÃO marca deleted_at' do
      message
      stub_uazapi_channel
      allow(ChannelUazapi::RevokeMessageService).to receive(:new)
        .and_return(instance_double(ChannelUazapi::RevokeMessageService, perform: { success: false, code: 500, error: 'boom' }))

      delete_message(message)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(message.reload.deleted_at).to be_nil
    end
  end

  context 'outgoing whatsapp ANTIGA (sem source_id)' do
    let(:message) do
      create(:message, message_type: :outgoing, account: account, inbox: inbox, conversation: conversation,
                       content: 'antiga', source_id: nil)
    end

    it 'soft delete local (deleted_for_recipient false), NÃO chama revoke' do
      message
      stub_uazapi_channel
      expect(ChannelUazapi::RevokeMessageService).not_to receive(:new)

      delete_message(message)
      expect(response).to have_http_status(:success)
      expect(message.reload.deleted_for_recipient).to be false
      expect(message.reload.deleted_at).to be_present
    end
  end
end

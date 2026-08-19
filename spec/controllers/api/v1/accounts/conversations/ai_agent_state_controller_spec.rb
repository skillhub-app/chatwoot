# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Conversation AI Agent State API', type: :request do
  let(:account) { create(:account) }
  let(:inbox)   { create(:inbox, account: account) }
  let(:agent_user) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:ai_agent) do
    AiAgent.create!(
      account: account, name: 'Test', language: 'pt', active: true,
      llm_provider: 'openai', llm_model: 'gpt-4o-mini',
      llm_api_key_encrypted: 'key'
    )
  end
  let!(:ai_conv) do
    AiAgentConversation.create!(
      ai_agent: ai_agent, conversation: conversation,
      contact: conversation.contact, state: 'active'
    )
  end

  before { create(:inbox_member, inbox: inbox, user: agent_user) }

  def base_url
    "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/ai_agent_state"
  end

  describe 'GET ai_agent_state' do
    context 'quando usuário não autenticado' do
      it 'retorna unauthorized' do
        get base_url
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'quando autenticado' do
      it 'retorna state atual da ai_agent_conversation' do
        get base_url,
            headers: { api_access_token: agent_user.access_token.token }
        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)['state']).to eq('active')
      end

      it 'retorna 404 quando não existe ai_agent_conversation' do
        ai_conv.destroy
        get base_url,
            headers: { api_access_token: agent_user.access_token.token }
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'PATCH ai_agent_state' do
    context 'state=active' do
      before { ai_conv.update!(state: 'paused') }

      it 'atualiza state para active' do
        patch base_url,
              params: { state: 'active' },
              headers: { api_access_token: agent_user.access_token.token }
        expect(response).to have_http_status(:ok)
        expect(ai_conv.reload.state).to eq('active')
      end

      it 'adiciona label ia_ligada e remove ia_desligada' do
        conversation.update!(label_list: ['ia_desligada'])
        patch base_url,
              params: { state: 'active' },
              headers: { api_access_token: agent_user.access_token.token }
        expect(conversation.reload.label_list).to include('ia_ligada')
        expect(conversation.reload.label_list).not_to include('ia_desligada')
      end
    end

    context 'state=paused' do
      it 'atualiza state para paused' do
        patch base_url,
              params: { state: 'paused' },
              headers: { api_access_token: agent_user.access_token.token }
        expect(response).to have_http_status(:ok)
        expect(ai_conv.reload.state).to eq('paused')
      end

      it 'adiciona label ia_desligada' do
        patch base_url,
              params: { state: 'paused' },
              headers: { api_access_token: agent_user.access_token.token }
        expect(conversation.reload.label_list).to include('ia_desligada')
      end
    end

    context "state='transferred' (não permitido via API)" do
      it 'retorna 422' do
        patch base_url,
              params: { state: 'transferred' },
              headers: { api_access_token: agent_user.access_token.token }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(ai_conv.reload.state).to eq('active')
      end
    end

    context "state='ended' (não permitido via API)" do
      it 'retorna 422' do
        patch base_url,
              params: { state: 'ended' },
              headers: { api_access_token: agent_user.access_token.token }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'garantia absoluta de etiqueta + activity (v65)' do
    let(:auth) { { api_access_token: agent_user.access_token.token } }

    it 'conversa sem etiqueta + liga → ia_ligada SOZINHA + activity' do
      ai_conv.update!(state: 'paused')
      conversation.update!(label_list: [])
      expect(AiAgent::ActivityService).to receive(:ai_enabled)

      patch base_url, params: { state: 'active' }, headers: auth

      expect(conversation.reload.label_list).to contain_exactly('ia_ligada')
    end

    it 'já active + liga de novo → ia_ligada sozinha, idempotente (SEM activity duplicada)' do
      ai_conv.update!(state: 'active')
      conversation.update!(label_list: ['ia_ligada'])
      expect(AiAgent::ActivityService).not_to receive(:ai_enabled)

      patch base_url, params: { state: 'active' }, headers: auth

      expect(conversation.reload.label_list).to contain_exactly('ia_ligada')
    end

    it 'com ia_ligada + desliga → ia_desligada SOZINHA + activity' do
      ai_conv.update!(state: 'active')
      conversation.update!(label_list: ['ia_ligada'])
      expect(AiAgent::ActivityService).to receive(:ai_disabled)

      patch base_url, params: { state: 'paused' }, headers: auth

      expect(conversation.reload.label_list).to contain_exactly('ia_desligada')
    end

    it 'reactivate de paused → ia_ligada sozinha + activity' do
      ai_conv.update!(state: 'paused')
      conversation.update!(label_list: ['ia_desligada'])
      expect(AiAgent::ActivityService).to receive(:ai_enabled)

      post "#{base_url}/reactivate", headers: auth

      expect(conversation.reload.label_list).to contain_exactly('ia_ligada')
    end
  end

  describe 'POST ai_agent_state/reactivate' do
    context 'de state=transferred (handoff via protocolo)' do
      before { ai_conv.update!(state: 'transferred', paused_reason: 'protocol:human') }

      it 'força state para active' do
        post "#{base_url}/reactivate",
             headers: { api_access_token: agent_user.access_token.token }
        expect(response).to have_http_status(:ok)
        expect(ai_conv.reload.state).to eq('active')
      end

      it 'limpa paused_reason' do
        post "#{base_url}/reactivate",
             headers: { api_access_token: agent_user.access_token.token }
        expect(ai_conv.reload.paused_reason).to be_nil
      end
    end

    context 'de state=ended (atendimento encerrado)' do
      before { ai_conv.update!(state: 'ended', paused_reason: 'protocol:unqualified') }

      it 'força state para active mesmo de ended' do
        post "#{base_url}/reactivate",
             headers: { api_access_token: agent_user.access_token.token }
        expect(response).to have_http_status(:ok)
        expect(ai_conv.reload.state).to eq('active')
      end

      it 'adiciona label ia_ligada' do
        post "#{base_url}/reactivate",
             headers: { api_access_token: agent_user.access_token.token }
        expect(conversation.reload.label_list).to include('ia_ligada')
      end
    end
  end
end

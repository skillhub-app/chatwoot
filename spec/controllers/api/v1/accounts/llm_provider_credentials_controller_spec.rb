require 'rails_helper'

RSpec.describe 'LLM Provider Credentials API', type: :request do
  let!(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  describe 'GET /api/v1/accounts/{account.id}/llm_provider_credentials' do
    it 'returns unauthorized for unauthenticated user' do
      get "/api/v1/accounts/#{account.id}/llm_provider_credentials"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'lists credentials of the account without exposing api_key' do
      create(:llm_provider_credential, account: account, provider: 'openai', api_key: 'sk-secret')
      create(:llm_provider_credential, account: create(:account), provider: 'gemini', api_key: 'other-secret')

      get "/api/v1/accounts/#{account.id}/llm_provider_credentials",
          headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      payload = response.parsed_body['payload']
      expect(payload.length).to eq(1)
      expect(payload.first['provider']).to eq('openai')
      expect(payload.first['has_api_key']).to be(true)
      expect(response.body).not_to include('sk-secret')
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/llm_provider_credentials' do
    it 'creates a new credential' do
      expect do
        post "/api/v1/accounts/#{account.id}/llm_provider_credentials",
             params: { provider: 'anthropic', api_key: 'sk-ant-123' },
             headers: admin.create_new_auth_token, as: :json
      end.to change(LlmProviderCredential, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['payload']['provider']).to eq('anthropic')
      expect(response.body).not_to include('sk-ant-123')
    end

    it 'upserts when provider already has a credential' do
      credential = create(:llm_provider_credential, account: account, provider: 'openai', api_key: 'old-key')

      expect do
        post "/api/v1/accounts/#{account.id}/llm_provider_credentials",
             params: { provider: 'openai', api_key: 'new-key' },
             headers: admin.create_new_auth_token, as: :json
      end.not_to change(LlmProviderCredential, :count)

      expect(response).to have_http_status(:created)
      expect(credential.reload.api_key).to eq('new-key')
    end

    it 'rejects invalid provider' do
      post "/api/v1/accounts/#{account.id}/llm_provider_credentials",
           params: { provider: 'cohere', api_key: 'key' },
           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/llm_provider_credentials/{id}' do
    it 'updates the api_key' do
      credential = create(:llm_provider_credential, account: account, provider: 'gemini', api_key: 'old')

      patch "/api/v1/accounts/#{account.id}/llm_provider_credentials/#{credential.id}",
            params: { api_key: 'rotated' },
            headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(credential.reload.api_key).to eq('rotated')
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/llm_provider_credentials/{id}' do
    it 'destroys the credential' do
      credential = create(:llm_provider_credential, account: account, provider: 'openai')

      expect do
        delete "/api/v1/accounts/#{account.id}/llm_provider_credentials/#{credential.id}",
               headers: admin.create_new_auth_token, as: :json
      end.to change(LlmProviderCredential, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end

    it 'does not allow destroying credential from another account' do
      credential = create(:llm_provider_credential, account: create(:account), provider: 'openai')

      delete "/api/v1/accounts/#{account.id}/llm_provider_credentials/#{credential.id}",
             headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Kanban::NotesController#external_create', type: :request do
  let(:account)       { create(:account) }
  let(:user)          { create(:user, account: account, role: :agent) }
  let(:other_account) { create(:account) }
  let(:other_user)    { create(:user, account: other_account, role: :agent) }

  let(:pipeline) { KanbanPipeline.create!(account: account, name: 'Sales', position: 0, visibility_type: 'all') }
  let(:stage)    { KanbanStage.create!(pipeline: pipeline, name: 'Lead', position: 0, probability: 0) }
  let(:item)     { KanbanItem.create!(account: account, pipeline: pipeline, stage: stage, title: 'Card', position: 0) }

  let(:url) { "/api/v1/accounts/#{account.id}/kanban/items/#{item.id}/notes" }

  describe 'POST /api/v1/accounts/:account_id/kanban/items/:id/notes' do
    context 'when unauthenticated' do
      it 'returns 401' do
        post url, params: { content: 'hello' }, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated with valid content' do
      it 'creates the note and returns 201' do
        post url, params: { content: 'Test note' }, headers: user.create_new_auth_token, as: :json
        expect(response).to have_http_status(:created)
        body = JSON.parse(response.body, symbolize_names: true)
        expect(body[:content]).to eq('Test note')
        expect(body[:kanban_item_id]).to eq(item.id)
        expect(body[:author][:id]).to eq(user.id)
      end

      it 'creates a KanbanNote record' do
        expect {
          post url, params: { content: 'Test note' }, headers: user.create_new_auth_token, as: :json
        }.to change(KanbanNote, :count).by(1)
      end

      it 'creates activity and sets metadata with author_name when provided' do
        post url, params: { content: 'Test note', author_name: 'n8n' },
                  headers: user.create_new_auth_token, as: :json
        activity = KanbanActivity.where(kanban_item: item, action_type: 'note_added').last
        expect(activity).not_to be_nil
        expect(activity.metadata['source']).to eq('api_external')
        expect(activity.metadata['author_name']).to eq('n8n')
      end

      it 'uses "API" as default author_name when not provided' do
        post url, params: { content: 'Test note' }, headers: user.create_new_auth_token, as: :json
        activity = KanbanActivity.where(kanban_item: item, action_type: 'note_added').last
        expect(activity.metadata['author_name']).to eq('API')
      end

      it 'returns author_name_external in response when provided' do
        post url, params: { content: 'Test note', author_name: 'n8n' },
                  headers: user.create_new_auth_token, as: :json
        body = JSON.parse(response.body, symbolize_names: true)
        expect(body[:author_name_external]).to eq('n8n')
      end

      it 'returns null author_name_external when not provided' do
        post url, params: { content: 'Test note' }, headers: user.create_new_auth_token, as: :json
        body = JSON.parse(response.body, symbolize_names: true)
        expect(body[:author_name_external]).to be_nil
      end
    end

    context 'when content is missing or blank' do
      it 'returns 422 when content is absent' do
        post url, params: {}, headers: user.create_new_auth_token, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'returns 422 when content is empty string' do
        post url, params: { content: '' }, headers: user.create_new_auth_token, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'returns 422 when content is nil' do
        post url, params: { content: nil }, headers: user.create_new_auth_token, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'when kanban_item does not exist' do
      it 'returns 404' do
        post "/api/v1/accounts/#{account.id}/kanban/items/999999/notes",
             params: { content: 'Test note' }, headers: user.create_new_auth_token, as: :json
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when kanban_item belongs to another account' do
      let(:other_pipeline) { KanbanPipeline.create!(account: other_account, name: 'Other', position: 0, visibility_type: 'all') }
      let(:other_stage)    { KanbanStage.create!(pipeline: other_pipeline, name: 'S', position: 0, probability: 0) }
      let(:other_item)     { KanbanItem.create!(account: other_account, pipeline: other_pipeline, stage: other_stage, title: 'X', position: 0) }

      it 'returns 404 for item from different account' do
        post "/api/v1/accounts/#{account.id}/kanban/items/#{other_item.id}/notes",
             params: { content: 'Test note' }, headers: user.create_new_auth_token, as: :json
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when author_name is too long' do
      it 'returns 422' do
        post url, params: { content: 'Test', author_name: 'a' * 101 },
                  headers: user.create_new_auth_token, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'regression: old nested route still works' do
      it 'POST /pipelines/:pid/items/:iid/notes returns 201' do
        post "/api/v1/accounts/#{account.id}/kanban/pipelines/#{pipeline.id}/items/#{item.id}/notes",
             params: { content: 'Via old route' }, headers: user.create_new_auth_token, as: :json
        expect(response).to have_http_status(:created)
      end
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'

# bug J: fetch_automation usava .where(pipelines: {...}) — alias inexistente
# (a tabela real é kanban_pipelines) — todo show/update/destroy de automação
# quebrava com PG::UndefinedTable, e nenhum dos 4 campos stop_on_* jamais
# persistia. Este spec cobre exatamente o caminho que estava 500ando em
# produção: PATCH no checkbox "IA desligada" (stop_on_ai_disabled).
RSpec.describe 'Api::V1::Accounts::Kanban::AutomationsController#update', type: :request do
  let(:account) { create(:account) }
  let(:user)    { create(:user, account: account, role: :agent) }

  let(:pipeline)  { KanbanPipeline.create!(account: account, name: 'Pré-Vendas', position: 0, visibility_type: 'all') }
  let(:stage)     { KanbanStage.create!(pipeline: pipeline, name: 'Em conversa', position: 0, probability: 0) }
  let(:automation) do
    KanbanAutomation.create!(
      pipeline: pipeline, trigger_stage: stage, name: 'Em conversa',
      stop_on_reply: false, stop_on_stage_change: true,
      stop_on_human_takeover: false, stop_on_ai_disabled: false
    )
  end

  let(:url) { "/api/v1/accounts/#{account.id}/kanban/automations/#{automation.id}" }

  describe 'PATCH /api/v1/accounts/:account_id/kanban/automations/:id' do
    it 'não estoura 500 (regressão do bug J)' do
      patch url, params: { stop_on_ai_disabled: true }, headers: user.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
    end

    it 'persiste stop_on_ai_disabled=true no banco' do
      patch url, params: { stop_on_ai_disabled: true }, headers: user.create_new_auth_token, as: :json
      expect(automation.reload.stop_on_ai_disabled).to be true
    end

    it 'persiste os outros 3 campos de condição de parada juntos' do
      patch url,
            params: { stop_on_reply: true, stop_on_stage_change: false, stop_on_human_takeover: true, stop_on_ai_disabled: true },
            headers: user.create_new_auth_token, as: :json

      automation.reload
      expect(automation.stop_on_reply).to be true
      expect(automation.stop_on_stage_change).to be false
      expect(automation.stop_on_human_takeover).to be true
      expect(automation.stop_on_ai_disabled).to be true
    end

    it 'GET show também não estoura mais 500' do
      get url, headers: user.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
    end

    it 'não permite acessar automação de outra conta' do
      other_account = create(:account)
      other_user    = create(:user, account: other_account, role: :agent)

      patch url, params: { stop_on_ai_disabled: true }, headers: other_user.create_new_auth_token, as: :json
      expect(response).to have_http_status(:not_found)
      expect(automation.reload.stop_on_ai_disabled).to be false
    end
  end
end

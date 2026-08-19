require 'rails_helper'

RSpec.describe GoogleCalendarCallbacksController, type: :controller do
  let(:account) { create(:account) }
  let(:agent)   { create(:ai_agent, account: account) }

  let(:valid_state) { "#{agent.id}:#{account.id}" }
  let(:valid_code)  { 'valid_oauth_code' }
  let(:token_data) do
    {
      'access_token'  => 'access_token_value',
      'refresh_token' => 'refresh_token_value',
      'expires_in'    => 3600
    }
  end

  before do
    allow(AiAgent::GoogleCalendar::AuthService).to receive(:exchange_code).and_return(token_data)
    # PrimaryCalendarSelectorService roda após salvar tokens; stub do calendarList
    # evita HTTP real (WebMock::NetConnectNotAllowedError não é StandardError e não
    # seria rescued). Por padrão retorna lista vazia (não seta calendar_id).
    stub_request(:get, %r{googleapis\.com/calendar/v3/users/me/calendarList})
      .to_return(status: 200, body: { 'items' => [] }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  describe 'GET #callback' do
    context 'com state e code válidos e agent existente' do
      it 'cria ai_agent_schedule e redireciona pra success' do
        expect {
          get :callback, params: { state: valid_state, code: valid_code }
        }.to change(AiAgentSchedule, :count).by(1)

        schedule = agent.reload.ai_agent_schedule
        expect(schedule.google_access_token_encrypted).to eq('access_token_value')
        expect(schedule.google_refresh_token_encrypted).to eq('refresh_token_value')
        expect(schedule.google_token_expires_at).to be_within(5.seconds).of(Time.current + 3600.seconds)
        expect(response).to redirect_to(
          "http://localhost:3000/app/accounts/#{account.id}/settings/ai-agents/#{agent.id}?calendar=connected"
        )
      end

      it 'atualiza schedule existente sem duplicar' do
        existing = agent.create_ai_agent_schedule!
        expect {
          get :callback, params: { state: valid_state, code: valid_code }
        }.not_to change(AiAgentSchedule, :count)

        existing.reload
        expect(existing.google_access_token_encrypted).to eq('access_token_value')
      end

      it 'aciona o PrimaryCalendarSelectorService após salvar os tokens' do
        selector = instance_double(AiAgent::GoogleCalendar::PrimaryCalendarSelectorService, call: 'primary@gmail.com')
        expect(AiAgent::GoogleCalendar::PrimaryCalendarSelectorService)
          .to receive(:new).with(an_instance_of(AiAgentSchedule)).and_return(selector)

        get :callback, params: { state: valid_state, code: valid_code }

        expect(response).to redirect_to(
          "http://localhost:3000/app/accounts/#{account.id}/settings/ai-agents/#{agent.id}?calendar=connected"
        )
      end

      it 'persiste a primary calendar selecionada (end-to-end)' do
        stub_request(:get, 'https://www.googleapis.com/calendar/v3/users/me/calendarList?maxResults=100')
          .to_return(
            status:  200,
            body:    { 'items' => [{ 'id' => 'primary@gmail.com', 'primary' => true }] }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        get :callback, params: { state: valid_state, code: valid_code }

        expect(agent.reload.ai_agent_schedule.google_calendar_id).to eq('primary@gmail.com')
      end

      it 'mantém o sucesso da conexão mesmo se a seleção da agenda falhar (graceful)' do
        allow_any_instance_of(AiAgent::GoogleCalendar::PrimaryCalendarSelectorService)
          .to receive(:call).and_return(nil)

        get :callback, params: { state: valid_state, code: valid_code }

        schedule = agent.reload.ai_agent_schedule
        expect(schedule.google_refresh_token_encrypted).to eq('refresh_token_value')
        expect(response).to redirect_to(
          "http://localhost:3000/app/accounts/#{account.id}/settings/ai-agents/#{agent.id}?calendar=connected"
        )
      end
    end

    context 'com state inválido (sem ":")' do
      it 'redireciona pra error sem criar schedule' do
        expect {
          get :callback, params: { state: 'invalido_sem_dois_pontos', code: valid_code }
        }.not_to change(AiAgentSchedule, :count)

        # account_id = nil → interpolação gera double-slash, comportamento esperado
        expect(response.location).to include('calendar=error')
      end
    end

    context 'com code em branco' do
      it 'redireciona pra error sem criar schedule' do
        expect {
          get :callback, params: { state: valid_state, code: '' }
        }.not_to change(AiAgentSchedule, :count)

        expect(response).to redirect_to(
          "http://localhost:3000/app/accounts/#{account.id}/settings/ai-agents?calendar=error"
        )
      end
    end

    context 'com agent_id que não existe' do
      it 'redireciona pra error sem criar schedule' do
        expect {
          get :callback, params: { state: "99999:#{account.id}", code: valid_code }
        }.not_to change(AiAgentSchedule, :count)

        expect(response).to redirect_to(
          "http://localhost:3000/app/accounts/#{account.id}/settings/ai-agents?calendar=error"
        )
      end
    end

    context 'quando exchange_code retorna blank' do
      before do
        allow(AiAgent::GoogleCalendar::AuthService).to receive(:exchange_code).and_return({})
      end

      it 'redireciona pra error sem criar schedule' do
        expect {
          get :callback, params: { state: valid_state, code: valid_code }
        }.not_to change(AiAgentSchedule, :count)

        expect(response).to redirect_to(
          "http://localhost:3000/app/accounts/#{account.id}/settings/ai-agents/#{agent.id}?calendar=error"
        )
      end
    end

    context 'quando exchange_code lança exception' do
      before do
        allow(AiAgent::GoogleCalendar::AuthService).to receive(:exchange_code)
          .and_raise(StandardError, 'Google token exchange failed')
      end

      it 'redireciona pra error e loga o erro' do
        expect(Rails.logger).to receive(:error).at_least(:once)
        expect {
          get :callback, params: { state: valid_state, code: valid_code }
        }.not_to change(AiAgentSchedule, :count)

        expect(response).to redirect_to(
          "http://localhost:3000/app/accounts/#{account.id}/settings/ai-agents/#{agent.id}?calendar=error"
        )
      end
    end
  end
end

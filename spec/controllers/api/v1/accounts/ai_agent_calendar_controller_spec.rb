require 'rails_helper'

RSpec.describe 'AiAgentCalendar internal endpoints', type: :request do
  let(:token)    { 'internal-secret-token' }
  let(:account)  { create(:account) }
  let(:ai_agent) { create(:ai_agent, account: account) }
  let(:contact)  { create(:contact, :with_phone_number, account: account) }
  let(:schedule) do
    ai_agent.create_ai_agent_schedule!(
      google_calendar_id:             'primary@gmail.com',
      google_refresh_token_encrypted: 'refresh',
      google_access_token_encrypted:  'access',
      google_token_expires_at:        1.hour.from_now,
      slot_duration_minutes:          60,
      min_notice_minutes:             0,
      weekly_windows:                 AiAgentSchedule::WEEKDAYS.index_with { [{ 'start' => '00:00', 'end' => '23:59' }] }
    )
  end

  before do
    schedule
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('INTERNAL_API_TOKEN', '').and_return(token)
  end

  def base_url(action)
    "/api/v1/accounts/#{account.id}/ai_agent_calendar/#{action}"
  end

  def auth_headers(t = token)
    { 'X-Internal-Token' => t }
  end

  def ctx
    { contact_id: contact.id, conversation_id: 'conv-1' }
  end

  describe 'autenticação por token interno' do
    it 'sem header => 401' do
      post base_url('consultar_horarios_livres'), params: { ai_agent_id: ai_agent.id, _context: ctx }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'token errado => 401' do
      post base_url('consultar_horarios_livres'),
           params: { ai_agent_id: ai_agent.id, _context: ctx }, headers: auth_headers('wrong'), as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'multi-tenant' do
    it 'ai_agent de outra account => 403' do
      other_agent = create(:ai_agent, account: create(:account))
      post base_url('consultar_horarios_livres'),
           params: { ai_agent_id: other_agent.id, _context: ctx }, headers: auth_headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe '_context obrigatório' do
    it 'sem _context => 400' do
      post base_url('consultar_horarios_livres'),
           params: { ai_agent_id: ai_agent.id }, headers: auth_headers, as: :json
      expect(response).to have_http_status(:bad_request)
    end
  end

  describe 'consultar_horarios_livres' do
    it 'retorna slots (200)' do
      stub_request(:post, 'https://www.googleapis.com/calendar/v3/freeBusy')
        .to_return(status: 200, body: { 'calendars' => { 'primary@gmail.com' => { 'busy' => [] } } }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      post base_url('consultar_horarios_livres'),
           params: { ai_agent_id: ai_agent.id, _context: ctx,
                     data_inicio: 1.day.from_now.iso8601, data_fim: 2.days.from_now.iso8601 },
           headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to have_key('slots')
    end
  end

  describe 'cancelar_agendamento — lead_phone SEMPRE do contato (anti-spoofing)' do
    it 'ignora lead_phone do input e usa o telefone do contato do _context' do
      real = contact.phone_number
      list_url = 'https://www.googleapis.com/calendar/v3/calendars/primary%40gmail.com/events'
      real_stub = stub_request(:get, list_url)
                  .with(query: hash_including('privateExtendedProperty' => "lead_phone=#{real}"))
                  .to_return(status: 200, body: { 'items' => [] }.to_json, headers: { 'Content-Type' => 'application/json' })
      spoof_stub = stub_request(:get, list_url)
                   .with(query: hash_including('privateExtendedProperty' => 'lead_phone=+5500000000000'))
                   .to_return(status: 200, body: { 'items' => [] }.to_json, headers: { 'Content-Type' => 'application/json' })

      post base_url('cancelar_agendamento'),
           params: { ai_agent_id: ai_agent.id, _context: ctx, lead_phone: '+5500000000000' },
           headers: auth_headers, as: :json

      expect(real_stub).to have_been_requested
      expect(spoof_stub).not_to have_been_requested
    end
  end

  describe 'criar_agendamento — resposta não vaza PII pro LLM' do
    it 'mensagem é legível e sem telefone/event_id; _audit guarda o telefone' do
      stub_request(:post, 'https://www.googleapis.com/calendar/v3/calendars/primary%40gmail.com/events')
        .to_return(status: 200, body: { 'id' => 'evt_secret', 'htmlLink' => 'https://cal/evt_secret' }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      post base_url('criar_agendamento'),
           params: { ai_agent_id: ai_agent.id, _context: ctx, data_hora_inicio: 1.day.from_now.iso8601, titulo: 'X' },
           headers: auth_headers, as: :json

      body = response.parsed_body
      expect(body['mensagem']).to be_present
      expect(body['mensagem']).not_to include(contact.phone_number)
      expect(body['mensagem']).not_to include('evt_secret')
      # audit (vai pro output_result) guarda o telefone derivado server-side
      expect(body.dig('_audit', 'lead_phone')).to eq(contact.phone_number)
    end
  end
end

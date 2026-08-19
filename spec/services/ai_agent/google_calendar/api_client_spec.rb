require 'rails_helper'

# Guarda de regressão para o bug do Faraday: um path com "/" inicial é tratado
# como absoluto e descarta o prefixo /calendar/v3 do BASE_URL. Todos os métodos
# devem bater na URL completa COM o prefixo.
RSpec.describe AiAgent::GoogleCalendar::ApiClient do
  let(:account)  { create(:account) }
  let(:ai_agent) { create(:ai_agent, account: account) }
  let(:schedule) do
    ai_agent.create_ai_agent_schedule!(
      google_refresh_token_encrypted: 'refresh_token_value',
      google_access_token_encrypted:  'access_token_value',
      google_token_expires_at:        1.hour.from_now
    )
  end

  let(:base)        { 'https://www.googleapis.com/calendar/v3' }
  let(:calendar_id) { 'primary@gmail.com' }
  let(:escaped_id)  { CGI.escape(calendar_id) } # primary%40gmail.com
  let(:time_min)    { Time.zone.parse('2026-06-21T00:00:00Z') }
  let(:time_max)    { Time.zone.parse('2026-06-28T00:00:00Z') }

  subject(:client) { described_class.new(schedule) }

  describe '#calendar_list' do
    it 'bate em /calendar/v3/users/me/calendarList (com prefixo)' do
      stub = stub_request(:get, "#{base}/users/me/calendarList")
             .with(query: { 'maxResults' => '100' })
             .to_return(status: 200, body: { 'items' => [{ 'id' => calendar_id, 'primary' => true }] }.to_json,
                        headers: { 'Content-Type' => 'application/json' })

      result = client.calendar_list

      expect(stub).to have_been_requested
      expect(result['items'].first['id']).to eq(calendar_id)
    end
  end

  describe '#freebusy' do
    it 'bate em /calendar/v3/freeBusy (com prefixo)' do
      stub = stub_request(:post, "#{base}/freeBusy")
             .to_return(status: 200, body: { 'calendars' => {} }.to_json,
                        headers: { 'Content-Type' => 'application/json' })

      client.freebusy(calendar_id, time_min, time_max)

      expect(stub).to have_been_requested
    end
  end

  describe '#create_event' do
    it 'bate em /calendar/v3/calendars/<id-escapado>/events (com prefixo)' do
      stub = stub_request(:post, "#{base}/calendars/#{escaped_id}/events")
             .to_return(status: 200, body: { 'id' => 'evt_1' }.to_json,
                        headers: { 'Content-Type' => 'application/json' })

      result = client.create_event(calendar_id, { summary: 'teste' })

      expect(stub).to have_been_requested
      expect(result['id']).to eq('evt_1')
    end
  end

  describe '#list_events' do
    it 'bate em /calendar/v3/calendars/<id-escapado>/events (com prefixo)' do
      stub = stub_request(:get, "#{base}/calendars/#{escaped_id}/events")
             .with(query: hash_including('singleEvents' => 'true', 'orderBy' => 'startTime'))
             .to_return(status: 200, body: { 'items' => [] }.to_json,
                        headers: { 'Content-Type' => 'application/json' })

      result = client.list_events(calendar_id, time_min, time_max)

      expect(stub).to have_been_requested
      expect(result['items']).to eq([])
    end
  end

  describe '#list_events_by_private_property' do
    it 'filtra por privateExtendedProperty e bate na URL com prefixo' do
      stub = stub_request(:get, "#{base}/calendars/#{escaped_id}/events")
             .with(query: hash_including('privateExtendedProperty' => 'lead_phone=+5519999990000',
                                         'singleEvents' => 'true'))
             .to_return(status: 200, body: { 'items' => [] }.to_json,
                        headers: { 'Content-Type' => 'application/json' })

      client.list_events_by_private_property(calendar_id, 'lead_phone', '+5519999990000', time_min: time_min)

      expect(stub).to have_been_requested
    end
  end

  describe '#delete_event' do
    it 'faz DELETE em /calendar/v3/calendars/<id>/events/<event_id> (com prefixo)' do
      stub = stub_request(:delete, "#{base}/calendars/#{escaped_id}/events/evt_1").to_return(status: 204, body: '')

      client.delete_event(calendar_id, 'evt_1')

      expect(stub).to have_been_requested
    end
  end

  describe 'token expirado com refresh falhando por invalid_grant (bug F)' do
    let(:expired_schedule) do
      ai_agent.create_ai_agent_schedule!(
        google_refresh_token_encrypted: 'dead_refresh_token',
        google_access_token_encrypted:  'stale_access_token',
        google_token_expires_at:        1.hour.ago
      )
    end

    before do
      stub_request(:post, 'https://oauth2.googleapis.com/token')
        .to_return(status: 400, body: { error: 'invalid_grant', error_description: 'Bad Request' }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
    end

    it 'notifica o InvalidGrantMonitor com o agente correto e ainda propaga o erro original' do
      allow(AiAgent::GoogleCalendar::InvalidGrantMonitor).to receive(:track!)

      expect { described_class.new(expired_schedule) }.to raise_error(/Google token refresh failed/)
      expect(AiAgent::GoogleCalendar::InvalidGrantMonitor).to have_received(:track!).with(ai_agent)
    end
  end

  describe 'path sem "/" inicial (regressão do bug)' do
    it 'NUNCA bate na raiz do host sem o prefixo /calendar/v3' do
      stub_request(:get, "#{base}/users/me/calendarList")
        .with(query: { 'maxResults' => '100' })
        .to_return(status: 200, body: { 'items' => [] }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      client.calendar_list

      expect(a_request(:get, 'https://www.googleapis.com/users/me/calendarList')).not_to have_been_made
    end
  end
end

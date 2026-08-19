require 'rails_helper'

RSpec.describe AiAgent::GoogleCalendar::EventCreatorService do
  let(:account)  { create(:account) }
  let(:ai_agent) { create(:ai_agent, account: account) }
  let(:schedule) do
    ai_agent.create_ai_agent_schedule!(
      google_calendar_id:             'primary@gmail.com',
      google_refresh_token_encrypted: 'refresh',
      google_access_token_encrypted:  'access',
      google_token_expires_at:        1.hour.from_now,
      slot_duration_minutes:          60,
      default_subject:                'Reunião com especialista'
    )
  end

  let(:events_url) { 'https://www.googleapis.com/calendar/v3/calendars/primary%40gmail.com/events' }
  let(:captured)   { [] }

  def stub_create(response_body = { 'id' => 'evt_123', 'htmlLink' => 'https://cal/evt_123' })
    stub_request(:post, events_url)
      .with(query: { 'conferenceDataVersion' => '1' })
      .to_return do |req|
        captured << JSON.parse(req.body)
        { status: 200, body: response_body.to_json, headers: { 'Content-Type' => 'application/json' } }
      end
  end

  # Resposta do Google com um Google Meet (entryPoint de vídeo).
  def body_with_meet(uri = 'https://meet.google.com/abc-defg-hij')
    {
      'id' => 'evt_123', 'htmlLink' => 'https://cal/evt_123',
      'conferenceData' => {
        'entryPoints' => [
          { 'entryPointType' => 'phone', 'uri' => 'tel:+551112345678' },
          { 'entryPointType' => 'video', 'uri' => uri }
        ]
      }
    }
  end

  def do_create(contact_email: nil)
    described_class.new(schedule,
                        data_hora_inicio: '2026-06-23T14:00:00-03:00',
                        titulo:           'Consulta',
                        lead_phone:       '+5519999990000',
                        conversation_id:  'conv-7',
                        ai_agent_id:      ai_agent.id,
                        contact_email:    contact_email).call
  end

  it 'força visibility: private' do
    stub_create
    do_create
    expect(captured.first['visibility']).to eq('private')
  end

  it 'grava extendedProperties.private com lead_phone, conversation_id e created_by' do
    stub_create
    do_create
    priv = captured.first.dig('extendedProperties', 'private')
    expect(priv['lead_phone']).to eq('+5519999990000')
    expect(priv['conversation_id']).to eq('conv-7')
    expect(priv['created_by']).to eq("ai_agent_#{ai_agent.id}")
  end

  it 'adiciona o lead como attendee quando há e-mail' do
    stub_create
    do_create(contact_email: 'lead@example.com')
    expect(captured.first['attendees']).to eq([{ 'email' => 'lead@example.com' }])
  end

  it 'sem e-mail: não adiciona attendee e põe o telefone na descrição' do
    stub_create
    do_create(contact_email: nil)
    expect(captured.first['attendees']).to be_nil
    expect(captured.first['description'].to_s).to include('Telefone contato: +5519999990000')
  end

  it 'retorna event_id e html_link no sucesso' do
    stub_create
    result = do_create
    expect(result[:status]).to eq('created')
    expect(result[:event_id]).to eq('evt_123')
    expect(result[:html_link]).to eq('https://cal/evt_123')
  end

  it 'envia conferenceData.createRequest (hangoutsMeet) no payload' do
    stub_create
    do_create
    cr = captured.first.dig('conferenceData', 'createRequest')
    expect(cr['conferenceSolutionKey']).to eq({ 'type' => 'hangoutsMeet' })
    expect(cr['requestId']).to be_present
  end

  it 'usa conferenceDataVersion=1 na chamada' do
    stub_create
    do_create
    expect(
      a_request(:post, events_url).with(query: { 'conferenceDataVersion' => '1' })
    ).to have_been_made
  end

  it 'captura o meet_link quando o Google retorna conferenceData' do
    stub_create(body_with_meet('https://meet.google.com/xyz-1234-abc'))
    result = do_create
    expect(result[:meet_link]).to eq('https://meet.google.com/xyz-1234-abc')
    expect(result[:meet_link_text]).to include('Link da reunião: https://meet.google.com/xyz-1234-abc')
  end

  it 'meet_link nil (graceful) quando o Google NÃO retorna conferenceData' do
    stub_create # body sem conferenceData
    result = do_create
    expect(result[:status]).to eq('created')
    expect(result[:html_link]).to eq('https://cal/evt_123')
    expect(result[:meet_link]).to be_nil
    expect(result[:meet_link_text]).to eq('')
  end

  it 'retorna erro legível (graceful) quando a API falha' do
    stub_request(:post, events_url).with(query: { 'conferenceDataVersion' => '1' }).to_return(status: 500, body: 'down')
    result = do_create
    expect(result[:status]).to eq('error')
    expect(result[:erro]).to be_present
  end
end

require 'rails_helper'

RSpec.describe AiAgent::GoogleCalendar::FreeSlotsFinderService do
  let(:account)  { create(:account) }
  let(:ai_agent) { create(:ai_agent, account: account) }
  let(:all_day_windows) do
    AiAgentSchedule::WEEKDAYS.index_with { [{ 'start' => '00:00', 'end' => '23:59' }] }
  end
  let(:schedule) do
    ai_agent.create_ai_agent_schedule!(
      google_calendar_id:             'primary@gmail.com',
      google_refresh_token_encrypted: 'refresh',
      google_access_token_encrypted:  'access',
      google_token_expires_at:        1.hour.from_now,
      slot_duration_minutes:          60,
      min_notice_minutes:             0,
      weekly_windows:                 all_day_windows
    )
  end

  let(:freebusy_url) { 'https://www.googleapis.com/calendar/v3/freeBusy' }

  def stub_freebusy(busy)
    stub_request(:post, freebusy_url).to_return(
      status:  200,
      body:    { 'calendars' => { 'primary@gmail.com' => { 'busy' => busy } } }.to_json,
      headers: { 'Content-Type' => 'application/json' }
    )
  end

  around { |ex| travel_to(Time.zone.local(2026, 6, 22, 6, 0, 0)) { ex.run } }

  it 'retorna apenas slots livres com a forma { inicio_iso, fim_iso, duracao_min }' do
    stub_freebusy([{ 'start' => '2026-06-22T10:00:00-03:00', 'end' => '2026-06-22T11:00:00-03:00' }])

    slots = described_class.new(schedule,
                                data_inicio: '2026-06-22T09:00:00-03:00',
                                data_fim:    '2026-06-22T12:00:00-03:00').call

    expect(slots).to be_an(Array)
    expect(slots).to be_present
    slots.each { |s| expect(s.keys).to contain_exactly(:inicio_iso, :fim_iso, :duracao_min) }
    # Nenhum slot sobrepõe o período ocupado 10:00-11:00.
    starts = slots.map { |s| Time.parse(s[:inicio_iso]) }
    expect(starts).not_to include(Time.parse('2026-06-22T10:00:00-03:00'))
  end

  it 'NUNCA chama list de eventos (só freebusy) — privacidade' do
    stub_freebusy([])
    described_class.new(schedule,
                        data_inicio: '2026-06-22T09:00:00-03:00',
                        data_fim:    '2026-06-22T12:00:00-03:00').call

    expect(a_request(:get, %r{/events})).not_to have_been_made
    expect(a_request(:post, freebusy_url)).to have_been_made
  end

  it 'retorna [] quando a agenda não está conectada' do
    schedule.update_columns(google_calendar_id: nil)
    expect(described_class.new(schedule, data_inicio: '2026-06-22T09:00:00-03:00',
                                         data_fim: '2026-06-22T12:00:00-03:00').call).to eq([])
  end

  it 'retorna [] (graceful) quando a API do Google falha' do
    stub_request(:post, freebusy_url).to_return(status: 500, body: 'boom')
    expect(described_class.new(schedule, data_inicio: '2026-06-22T09:00:00-03:00',
                                         data_fim: '2026-06-22T12:00:00-03:00').call).to eq([])
  end
end

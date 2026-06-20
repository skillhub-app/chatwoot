require 'rails_helper'

RSpec.describe AiAgent::GoogleCalendar::EventCancelerService do
  let(:account)  { create(:account) }
  let(:ai_agent) { create(:ai_agent, account: account) }
  let(:schedule) do
    ai_agent.create_ai_agent_schedule!(
      google_calendar_id:             'primary@gmail.com',
      google_refresh_token_encrypted: 'refresh',
      google_access_token_encrypted:  'access',
      google_token_expires_at:        1.hour.from_now
    )
  end

  let(:lead_phone) { '+5519999990000' }
  let(:list_url)   { 'https://www.googleapis.com/calendar/v3/calendars/primary%40gmail.com/events' }

  def event(id, phone)
    { 'id' => id, 'extendedProperties' => { 'private' => { 'lead_phone' => phone } } }
  end

  def stub_list(items)
    stub_request(:get, list_url).with(query: hash_including('privateExtendedProperty' => "lead_phone=#{lead_phone}"))
                                .to_return(status: 200, body: { 'items' => items }.to_json,
                                           headers: { 'Content-Type' => 'application/json' })
  end

  def stub_delete(id)
    stub_request(:delete, "#{list_url}/#{id}").to_return(status: 204, body: '')
  end

  it 'retorna erro quando não encontra nenhum evento do lead' do
    stub_list([])
    result = described_class.new(schedule, lead_phone: lead_phone).call
    expect(result[:cancelled_count]).to eq(0)
    expect(result[:status]).to eq('not_found')
    expect(result[:erro]).to eq(described_class::NOT_FOUND)
  end

  it 'cancela 1 evento do lead' do
    stub_list([event('evt_1', lead_phone)])
    del = stub_delete('evt_1')
    result = described_class.new(schedule, lead_phone: lead_phone).call
    expect(del).to have_been_requested
    expect(result).to include(cancelled_count: 1, status: 'cancelled')
  end

  it 'cancela TODOS quando há mais de um' do
    stub_list([event('evt_1', lead_phone), event('evt_2', lead_phone)])
    stub_delete('evt_1')
    stub_delete('evt_2')
    result = described_class.new(schedule, lead_phone: lead_phone).call
    expect(result[:cancelled_count]).to eq(2)
  end

  it 'NUNCA cancela evento cujo extendedProperties.private.lead_phone não bate (defesa)' do
    # API devolve um item de outro lead — o serviço re-checa e ignora.
    stub_list([event('evt_outro', '+5511888887777')])
    described_class.new(schedule, lead_phone: lead_phone).call
    expect(a_request(:delete, "#{list_url}/evt_outro")).not_to have_been_made
  end

  it 'lead_phone em branco => erro, sem chamar API' do
    result = described_class.new(schedule, lead_phone: '').call
    expect(result[:status]).to eq('not_found')
    expect(a_request(:get, list_url)).not_to have_been_made
  end

  it 'retorna erro legível (graceful) quando a API falha' do
    stub_request(:get, list_url).to_return(status: 500, body: 'down')
    result = described_class.new(schedule, lead_phone: lead_phone).call
    expect(result[:status]).to eq('error')
    expect(result[:erro]).to be_present
  end
end

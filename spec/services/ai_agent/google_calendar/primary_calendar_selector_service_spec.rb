require 'rails_helper'

RSpec.describe AiAgent::GoogleCalendar::PrimaryCalendarSelectorService do
  let(:account)  { create(:account) }
  let(:ai_agent) { create(:ai_agent, account: account) }
  let(:schedule) do
    ai_agent.create_ai_agent_schedule!(
      google_refresh_token_encrypted: 'refresh_token_value',
      google_access_token_encrypted:  'access_token_value',
      google_token_expires_at:        1.hour.from_now
    )
  end

  let(:calendar_list_url) { 'https://www.googleapis.com/calendar/v3/users/me/calendarList?maxResults=100' }

  def stub_calendar_list(status:, body:)
    stub_request(:get, calendar_list_url)
      .to_return(status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  describe '#call' do
    context 'quando google_calendar_id já está preenchido' do
      before { schedule.update_column(:google_calendar_id, 'already@set.com') }

      it 'não chama a API e mantém o valor' do
        result = described_class.new(schedule).call

        expect(result).to be_nil
        expect(a_request(:get, calendar_list_url)).not_to have_been_made
        expect(schedule.reload.google_calendar_id).to eq('already@set.com')
      end
    end

    context 'quando refresh_token está blank' do
      before { schedule.update_column(:google_refresh_token_encrypted, nil) }

      it 'não chama a API e não seta nada' do
        result = described_class.new(schedule).call

        expect(result).to be_nil
        expect(a_request(:get, calendar_list_url)).not_to have_been_made
        expect(schedule.reload.google_calendar_id).to be_blank
      end
    end

    context 'quando a API retorna 200 com uma primary calendar' do
      before do
        stub_calendar_list(status: 200, body: {
                             'items' => [
                               { 'id' => 'secundaria@group.calendar.google.com', 'primary' => false },
                               { 'id' => 'primary@gmail.com',                     'primary' => true }
                             ]
                           })
      end

      it 'seta a primary como google_calendar_id' do
        result = described_class.new(schedule).call

        expect(result).to eq('primary@gmail.com')
        expect(schedule.reload.google_calendar_id).to eq('primary@gmail.com')
      end
    end

    context 'quando a API retorna 200 sem nenhuma primary' do
      before do
        stub_calendar_list(status: 200, body: {
                             'items' => [
                               { 'id' => 'primeira@gmail.com',  'primary' => false },
                               { 'id' => 'segunda@gmail.com',   'primary' => false }
                             ]
                           })
      end

      it 'seta o primeiro item da lista' do
        result = described_class.new(schedule).call

        expect(result).to eq('primeira@gmail.com')
        expect(schedule.reload.google_calendar_id).to eq('primeira@gmail.com')
      end
    end

    context 'quando a API retorna 200 com items vazio' do
      before { stub_calendar_list(status: 200, body: { 'items' => [] }) }

      it 'não seta nada' do
        result = described_class.new(schedule).call

        expect(result).to be_nil
        expect(schedule.reload.google_calendar_id).to be_blank
      end
    end

    context 'quando a API retorna 401' do
      before { stub_calendar_list(status: 401, body: { 'error' => 'invalid_credentials' }) }

      it 'loga o erro e não seta nada (graceful)' do
        expect(Rails.logger).to receive(:error).at_least(:once)

        result = described_class.new(schedule).call

        expect(result).to be_nil
        expect(schedule.reload.google_calendar_id).to be_blank
      end
    end

    context 'quando o ApiClient levanta uma exception' do
      before do
        allow(AiAgent::GoogleCalendar::ApiClient).to receive(:new).and_raise(StandardError, 'boom')
      end

      it 'loga o erro e retorna nil sem propagar (graceful)' do
        expect(Rails.logger).to receive(:error).at_least(:once)

        expect { @result = described_class.new(schedule).call }.not_to raise_error
        expect(@result).to be_nil
        expect(schedule.reload.google_calendar_id).to be_blank
      end
    end
  end
end

require 'rails_helper'

RSpec.describe AiAgent::GoogleCalendar::AuthService do
  let(:client_id)     { 'test_client_id' }
  let(:client_secret) { 'test_client_secret' }
  let(:redirect_uri)  { 'https://crm.volps.com.br/google_calendar/callback' }

  before do
    allow(described_class).to receive(:client_id).and_return(client_id)
    allow(described_class).to receive(:client_secret).and_return(client_secret)
  end

  describe '.authorization_url' do
    it 'gera URL com redirect_uri sem prefixo /auth' do
      url = described_class.authorization_url(redirect_uri, state: '3:1')

      expect(url).to start_with('https://accounts.google.com/o/oauth2/v2/auth')
      expect(url).to include("redirect_uri=#{CGI.escape(redirect_uri)}")
      expect(url).to include('access_type=offline')
      expect(url).to include('prompt=consent')
      expect(url).to include("client_id=#{client_id}")
      expect(url).to include("state=3%3A1")
      expect(url).not_to include('/auth/google_calendar')
    end
  end

  describe '.exchange_code' do
    it 'faz POST no token endpoint e retorna access_token + refresh_token' do
      stub_response = {
        'access_token'  => 'new_access_token',
        'refresh_token' => 'new_refresh_token',
        'expires_in'    => 3600,
        'token_type'    => 'Bearer'
      }

      stub_request(:post, 'https://oauth2.googleapis.com/token')
        .with(body: hash_including(
          'code'          => 'auth_code_123',
          'client_id'     => client_id,
          'client_secret' => client_secret,
          'redirect_uri'  => redirect_uri,
          'grant_type'    => 'authorization_code'
        ))
        .to_return(
          status: 200,
          body:   stub_response.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      result = described_class.exchange_code('auth_code_123', redirect_uri)

      expect(result['access_token']).to eq('new_access_token')
      expect(result['refresh_token']).to eq('new_refresh_token')
    end
  end
end

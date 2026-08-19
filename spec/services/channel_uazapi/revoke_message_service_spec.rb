# frozen_string_literal: true

require 'rails_helper'

# Sprint v68 — revoke (apaga no WhatsApp do lead) via Uazapi.
RSpec.describe ChannelUazapi::RevokeMessageService do
  let(:channel) do
    instance_double(Channel::Uazapi, api_base_url: 'https://api.uazapi.com', uazapi_instance_token: 'tok123')
  end
  let(:source_id) { 'WAMSG-ABC' }
  let(:url) { 'https://api.uazapi.com/message/delete' }

  subject(:result) { described_class.new(channel, source_id).perform }

  context 'quando source_id está em branco' do
    let(:source_id) { '' }

    it 'falha sem chamar a API' do
      expect(result).to eq(success: false, error: 'missing_source_id')
    end
  end

  context 'HTTP 200' do
    before { stub_request(:post, url).to_return(status: 200, body: { id: source_id }.to_json, headers: { 'Content-Type' => 'application/json' }) }

    it 'retorna success: true' do
      expect(result[:success]).to be true
      expect(result[:code]).to eq 200
    end

    it 'envia body {id:} e header token' do
      result
      expect(a_request(:post, url).with(body: { id: source_id }.to_json, headers: { 'token' => 'tok123' })).to have_been_made
    end
  end

  context 'HTTP 404 (já apagada) → idempotente, sucesso' do
    before { stub_request(:post, url).to_return(status: 404, body: { error: 'not found' }.to_json, headers: { 'Content-Type' => 'application/json' }) }

    it 'retorna success: true' do
      expect(result[:success]).to be true
      expect(result[:code]).to eq 404
    end
  end

  [400, 401, 500].each do |code|
    context "HTTP #{code} → falha" do
      before { stub_request(:post, url).to_return(status: code, body: { message: "err #{code}" }.to_json, headers: { 'Content-Type' => 'application/json' }) }

      it 'retorna success: false com o código' do
        expect(result[:success]).to be false
        expect(result[:code]).to eq code
      end
    end
  end

  context 'timeout' do
    before { stub_request(:post, url).to_timeout }

    it 'falha graceful com error: timeout' do
      expect(result[:success]).to be false
      expect(result[:error]).to eq 'timeout'
    end
  end

  context 'código inesperado (418)' do
    before { stub_request(:post, url).to_return(status: 418, body: '') }

    it 'retorna success: false' do
      expect(result[:success]).to be false
      expect(result[:code]).to eq 418
    end
  end
end

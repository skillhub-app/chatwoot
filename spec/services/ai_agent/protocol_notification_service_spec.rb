# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiAgent::ProtocolNotificationService do
  let(:account) { create(:account) }
  let(:phone)   { '+5511999990000' }
  let(:summary) { 'Lead perguntou sobre preços. Proposta enviada.' }

  def set_config(name, value)
    InstallationConfig.find_or_initialize_by(name: name).tap do |c|
      c.value = value
      c.save!
    end
  end

  before do
    set_config('UAZAPI_BASE_URL',               'https://uazapi.example.com')
    set_config('UAZAPI_ADMIN_TOKEN',             'admin-token-123')
    set_config('UAZAPI_NOTIFICATION_INSTANCE',   'notificacao')
  end

  describe '#call' do
    context 'configuração completa e UazAPI retorna 200' do
      before do
        stub_request(:post, 'https://uazapi.example.com/message/sendText/notificacao')
          .to_return(status: 200, body: '{"status":"sent"}', headers: { 'Content-Type' => 'application/json' })
      end

      it 'envia POST para a instância de notificação' do
        described_class.call(phone: phone, summary: summary, account: account)
        expect(WebMock).to have_requested(:post, 'https://uazapi.example.com/message/sendText/notificacao')
          .with(body: hash_including('number' => '5511999990000'))
      end

      it 'inclui o texto da notificação no body' do
        described_class.call(phone: phone, summary: summary, account: account)
        expect(WebMock).to have_requested(:post, 'https://uazapi.example.com/message/sendText/notificacao')
          .with(body: hash_including('text' => a_string_including(summary)))
      end

      it 'sanitiza o número removendo caracteres não numéricos' do
        described_class.call(phone: '+55 (11) 99999-0000', summary: summary, account: account)
        expect(WebMock).to have_requested(:post, 'https://uazapi.example.com/message/sendText/notificacao')
          .with(body: hash_including('number' => '5511999990000'))
      end
    end

    context 'UAZAPI_NOTIFICATION_INSTANCE não configurado' do
      before { InstallationConfig.find_by(name: 'UAZAPI_NOTIFICATION_INSTANCE')&.destroy }

      it 'não envia requisição HTTP' do
        described_class.call(phone: phone, summary: summary, account: account)
        expect(WebMock).not_to have_requested(:post, /uazapi/)
      end

      it 'loga warning' do
        expect(Rails.logger).to receive(:warn).with(/UAZAPI_NOTIFICATION_INSTANCE/)
        described_class.call(phone: phone, summary: summary, account: account)
      end
    end

    context 'UAZAPI_BASE_URL ausente' do
      before { InstallationConfig.find_by(name: 'UAZAPI_BASE_URL')&.destroy }

      it 'não envia requisição HTTP' do
        described_class.call(phone: phone, summary: summary, account: account)
        expect(WebMock).not_to have_requested(:post, /uazapi/)
      end

      it 'loga error' do
        expect(Rails.logger).to receive(:error).with(/UAZAPI_BASE_URL/)
        described_class.call(phone: phone, summary: summary, account: account)
      end
    end

    context 'phone em branco' do
      it 'retorna sem enviar requisição' do
        described_class.call(phone: '', summary: summary, account: account)
        expect(WebMock).not_to have_requested(:post, /uazapi/)
      end
    end

    context 'summary em branco' do
      it 'retorna sem enviar requisição' do
        described_class.call(phone: phone, summary: nil, account: account)
        expect(WebMock).not_to have_requested(:post, /uazapi/)
      end
    end

    context 'UazAPI retorna erro 5xx' do
      before do
        stub_request(:post, 'https://uazapi.example.com/message/sendText/notificacao')
          .to_return(status: 500, body: '{"message":"internal error"}',
                     headers: { 'Content-Type' => 'application/json' })
      end

      it 'não levanta exceção' do
        expect {
          described_class.call(phone: phone, summary: summary, account: account)
        }.not_to raise_error
      end

      it 'loga o erro de resposta' do
        expect(Rails.logger).to receive(:error).with(/ProtocolNotify.*500/)
        described_class.call(phone: phone, summary: summary, account: account)
      end
    end

    context 'Faraday levanta exceção de rede' do
      before do
        stub_request(:post, 'https://uazapi.example.com/message/sendText/notificacao')
          .to_raise(Faraday::ConnectionFailed.new('connection refused'))
      end

      it 'não levanta exceção (graceful degradation)' do
        expect {
          described_class.call(phone: phone, summary: summary, account: account)
        }.not_to raise_error
      end

      it 'loga o erro' do
        expect(Rails.logger).to receive(:error).with(/ProtocolNotify.*connection refused/)
        described_class.call(phone: phone, summary: summary, account: account)
      end
    end
  end
end

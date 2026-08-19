# frozen_string_literal: true

require 'rails_helper'

# Sprint v68 — captura do source_id (key.id) no envio, pré-requisito do revoke.
RSpec.describe ChannelUazapi::SendOnUazapiService do
  let(:message) { create(:message, message_type: :outgoing) }

  subject(:service) { described_class.new(message: message) }

  describe '#extract_source_id' do
    it 'extrai de key.id' do
      expect(service.send(:extract_source_id, { 'key' => { 'id' => 'WA1' } })).to eq('WA1')
    end

    it 'extrai de id no topo' do
      expect(service.send(:extract_source_id, { 'id' => 'WA2' })).to eq('WA2')
    end

    it 'extrai de data.key.id' do
      expect(service.send(:extract_source_id, { 'data' => { 'key' => { 'id' => 'WA3' } } })).to eq('WA3')
    end

    it 'retorna nil quando não há id' do
      expect(service.send(:extract_source_id, { 'foo' => 'bar' })).to be_nil
    end

    it 'retorna nil para resposta não-hash' do
      expect(service.send(:extract_source_id, nil)).to be_nil
      expect(service.send(:extract_source_id, 'texto')).to be_nil
    end
  end

  describe '#store_source_id' do
    it 'grava o source_id na mensagem' do
      service.send(:store_source_id, { 'key' => { 'id' => 'WA-STORED' } })
      expect(message.reload.source_id).to eq('WA-STORED')
    end

    it 'não grava quando a resposta não tem id' do
      service.send(:store_source_id, { 'foo' => 'bar' })
      expect(message.reload.source_id).to be_nil
    end
  end
end

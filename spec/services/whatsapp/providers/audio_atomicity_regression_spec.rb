# frozen_string_literal: true

require 'rails_helper'

# Sprint v68 — regressão de roteamento do WhatsappCloudService.
# Garante que uma mensagem de áudio (content nil + anexo) SEMPRE é roteada
# para send_attachment_message e NUNCA para send_text_message — que seria a
# origem do text.body: nil rejeitado pelo Meta (HTTP 400). Este serviço NÃO
# foi alterado na v68; o teste blinda o comportamento que o fix de
# atomicidade passou a depender.
describe Whatsapp::Providers::WhatsappCloudService do
  subject(:service) { described_class.new(whatsapp_channel: whatsapp_channel) }

  let(:whatsapp_channel) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
  end
  let(:conversation) { create(:conversation, inbox: whatsapp_channel.inbox) }
  let(:phone) { '+5511999999999' }

  before do
    stub_request(:get, %r{graph\.facebook\.com/.*/message_templates})
  end

  def audio_message(content: nil)
    message = create(:message, conversation: conversation, message_type: :outgoing,
                               content: content, inbox: whatsapp_channel.inbox)
    attachment = message.attachments.new(account_id: message.account_id, file_type: :audio)
    attachment.file.attach(io: StringIO.new('mp3bytes'), filename: 'resposta.mp3', content_type: 'audio/mpeg')
    attachment.save!
    message.reload
  end

  describe '#send_message routing' do
    it 'áudio com content nil → send_attachment_message, NUNCA send_text_message (regressão do bug v68)' do
      expect(service).to receive(:send_attachment_message).once
      expect(service).not_to receive(:send_text_message)

      service.send_message(phone, audio_message)
    end

    it 'só content (sem anexo) → send_text_message' do
      message = create(:message, conversation: conversation, message_type: :outgoing,
                                 content: 'olá', inbox: whatsapp_channel.inbox)

      expect(service).to receive(:send_text_message).once
      expect(service).not_to receive(:send_attachment_message)

      service.send_message(phone, message)
    end

    it 'content + anexo → send_attachment_message (não regrediu)' do
      expect(service).to receive(:send_attachment_message).once
      expect(service).not_to receive(:send_text_message)

      service.send_message(phone, audio_message(content: 'legenda'))
    end
  end
end

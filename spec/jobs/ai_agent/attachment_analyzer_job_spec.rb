require 'rails_helper'

RSpec.describe AiAgent::AttachmentAnalyzerJob do
  let(:account)      { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:message)      { create(:message, account: account, conversation: conversation, message_type: :incoming) }

  def build_attachment(type, content_type)
    att = message.attachments.create!(account_id: account.id, file_type: type)
    att.file.attach(io: StringIO.new('x'), filename: "f.#{type == :image ? 'png' : 'pdf'}", content_type: content_type)
    att
  end

  before { allow(AiAgent::IncomingMessageProcessor).to receive(:call) }

  it 'imagem: grava image_description + ai_analyzed e re-processa a mensagem' do
    att = build_attachment(:image, 'image/png')
    allow_any_instance_of(AiAgent::AttachmentAnalyzerService).to receive(:analyze_image).and_return('uma foto de um documento')

    described_class.perform_now(att.id)

    att.reload
    expect(att.meta['image_description']).to eq('uma foto de um documento')
    expect(att.meta['ai_analyzed']).to be(true)
    expect(AiAgent::IncomingMessageProcessor).to have_received(:call).with(message)
  end

  it 'pdf (file): grava pdf_text + ai_analyzed' do
    att = build_attachment(:file, 'application/pdf')
    allow_any_instance_of(AiAgent::AttachmentAnalyzerService).to receive(:analyze_pdf).and_return('texto do contrato')

    described_class.perform_now(att.id)

    expect(att.reload.meta).to include('pdf_text' => 'texto do contrato', 'ai_analyzed' => true)
  end

  it 'falha do analyzer: marca ai_analyzed (graceful), não levanta, mensagem segue' do
    att = build_attachment(:image, 'image/png')
    allow_any_instance_of(AiAgent::AttachmentAnalyzerService).to receive(:analyze_image).and_raise(StandardError, 'boom')

    expect { described_class.perform_now(att.id) }.not_to raise_error
    att.reload
    expect(att.meta['ai_analyzed']).to be(true)
    expect(att.meta['image_description']).to be_nil
    expect(AiAgent::IncomingMessageProcessor).to have_received(:call).with(message)
  end
end

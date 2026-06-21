require 'rails_helper'

RSpec.describe AiAgent::AttachmentAnalyzerService do
  let(:account)      { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:message)      { create(:message, account: account, conversation: conversation, message_type: :incoming) }
  let(:fake_client)  { double('OpenAI::Client') }

  subject(:service) { described_class.new }

  def image_attachment
    att = message.attachments.create!(account_id: account.id, file_type: :image)
    att.file.attach(io: Rails.root.join('spec/assets/sample.png').open, filename: 'sample.png', content_type: 'image/png')
    att
  end

  def pdf_attachment
    att = message.attachments.create!(account_id: account.id, file_type: :file)
    att.file.attach(io: StringIO.new('%PDF-1.4 fake'), filename: 'doc.pdf', content_type: 'application/pdf')
    att
  end

  describe '#analyze_image' do
    before { allow(service).to receive(:client).and_return(fake_client) }

    it 'chama o LLM (gpt-4.1-nano) com a imagem e retorna a descrição' do
      expect(fake_client).to receive(:chat)
        .with(hash_including(parameters: hash_including(model: 'gpt-4.1-nano')))
        .and_return({ 'choices' => [{ 'message' => { 'content' => 'Uma pessoa sorrindo.' } }] })

      expect(service.analyze_image(image_attachment)).to eq('Uma pessoa sorrindo.')
    end

    it 'graceful: sem chave OpenAI configurada retorna nil' do
      allow(service).to receive(:client).and_return(nil)
      expect(service.analyze_image(image_attachment)).to be_nil
    end
  end

  describe '#analyze_pdf' do
    before { allow(service).to receive(:client).and_return(fake_client) }

    it 'PDF curto (<2000 chars): retorna o texto puro, sem chamar o LLM' do
      allow(PDF::Reader).to receive(:new).and_return(double('reader', pages: [double(text: 'Contrato curto.')]))
      expect(fake_client).not_to receive(:chat)

      expect(service.analyze_pdf(pdf_attachment)).to eq('Contrato curto.')
    end

    it 'PDF longo (>2000 chars): resume via LLM (gpt-4.1-mini)' do
      allow(PDF::Reader).to receive(:new).and_return(double('reader', pages: [double(text: 'a' * 2500)]))
      expect(fake_client).to receive(:chat)
        .with(hash_including(parameters: hash_including(model: 'gpt-4.1-mini')))
        .and_return({ 'choices' => [{ 'message' => { 'content' => 'Resumo do documento.' } }] })

      expect(service.analyze_pdf(pdf_attachment)).to eq('Resumo do documento.')
    end

    it 'graceful: PDF ilegível (DOC/scaneado/criptografado) retorna nil' do
      allow(PDF::Reader).to receive(:new).and_raise(StandardError, 'PDF encrypted')
      expect(service.analyze_pdf(pdf_attachment)).to be_nil
    end
  end
end

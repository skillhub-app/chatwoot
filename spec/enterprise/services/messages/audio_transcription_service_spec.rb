require 'rails_helper'

RSpec.describe Messages::AudioTranscriptionService, type: :service do
  let(:account) { create(:account, audio_transcriptions: true) }
  let(:conversation) { create(:conversation, account: account) }
  let(:message) { create(:message, conversation: conversation) }
  let(:attachment) { message.attachments.create!(account: account, file_type: :audio) }

  before do
    # Create required installation configs
    InstallationConfig.find_or_create_by!(name: 'CAPTAIN_OPEN_AI_API_KEY') { |config| config.value = 'test-api-key' }
    InstallationConfig.find_or_create_by!(name: 'CAPTAIN_OPEN_AI_MODEL') { |config| config.value = 'gpt-4o-mini' }

    # Mock usage limits for transcription to be available
    allow(account).to receive(:usage_limits).and_return({ captain: { responses: { current_available: 100 } } })

    # Suppress IncomingMessageProcessor calls from Message#after_create_commit during
    # factory setup. Tests that verify the call use expect(...).to receive overrides.
    allow(AiAgent::IncomingMessageProcessor).to receive(:call)
  end

  describe '#perform' do
    let(:service) { described_class.new(attachment) }

    context 'when captain_integration feature is not enabled' do
      before do
        account.disable_features!('captain_integration')
      end

      it 'returns transcription limit exceeded' do
        expect(service.perform).to eq({ error: 'Transcription limit exceeded' })
      end
    end

    context 'when transcription is successful' do
      before do
        # Mock can_transcribe? to return true and transcribe_audio method
        allow(service).to receive(:can_transcribe?).and_return(true)
        allow(service).to receive(:transcribe_audio).and_return('Hello world transcription')
      end

      it 'returns successful transcription' do
        result = service.perform
        expect(result).to eq({ success: true, transcriptions: 'Hello world transcription' })
      end
    end

    context 'when audio transcriptions are disabled' do
      before do
        account.update!(audio_transcriptions: false)
      end

      it 'returns error for transcription limit exceeded' do
        result = service.perform
        expect(result).to eq({ error: 'Transcription limit exceeded' })
      end
    end

    context 'when attachment already has transcribed text' do
      before do
        attachment.update!(meta: { transcribed_text: 'Existing transcription' })
        allow(service).to receive(:can_transcribe?).and_return(true)
      end

      it 'returns existing transcription without calling API' do
        result = service.perform
        expect(result).to eq({ success: true, transcriptions: 'Existing transcription' })
      end
    end
  end

  describe '#update_transcription (private)' do
    let(:service) { described_class.new(attachment) }

    before do
      allow(account).to receive(:increment_response_usage)
      allow_any_instance_of(Message).to receive(:send_update_event)
    end

    context 'quando transcribed_text tem conteúdo' do
      it 'dispara AiAgent::IncomingMessageProcessor com a mensagem' do
        expect(AiAgent::IncomingMessageProcessor).to receive(:call).with(message)
        service.send(:update_transcription, 'Olá, tudo bem?')
      end
    end

    context 'quando transcribed_text está em branco' do
      it 'retorna sem salvar transcrição (return antecipado)' do
        # update_transcription returns early when blank — attachment is never touched
        expect(attachment).not_to receive(:update!)
        service.send(:update_transcription, '')
      end
    end

    context 'loop infinito impossível — attachment já tem transcrição' do
      before { attachment.update!(meta: { transcribed_text: 'já transcrito' }) }

      it 'audio_pending_transcription? retorna false (não bloqueia na 2ª chamada)' do
        # Once transcription is saved, audio_pending_transcription? must return false
        # so the processor continues rather than being blocked indefinitely.
        account.update!(audio_transcriptions: true)
        processor = AiAgent::IncomingMessageProcessor.new(message)
        expect(processor.send(:audio_pending_transcription?)).to eq(false)
      end
    end
  end

  describe '#fetch_audio_file' do
    let(:service) { described_class.new(attachment) }

    before do
      attachment.file.attach(
        io: File.open(Rails.public_path.join('audio/widget/ding.mp3')),
        filename: 'speech',
        content_type: 'audio/mpeg'
      )
    end

    it 'adds extension from content type when filename has no extension' do
      temp_file_path = service.send(:fetch_audio_file)

      expect(File.extname(temp_file_path)).to eq('.mpeg')
    ensure
      FileUtils.rm_f(temp_file_path) if temp_file_path.present?
    end
  end
end

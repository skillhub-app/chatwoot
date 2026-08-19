# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiAgent::TtsService do
  let(:agent) do
    double(
      'AiAgent',
      tts_enabled?:          true,
      tts_voice_id:          'voice123',
      tts_api_key_encrypted: 'sk-test-key'
    )
  end

  let(:elevenlabs_url) { "https://api.elevenlabs.io/v1/text-to-speech/#{agent.tts_voice_id}" }

  before do
    stub_request(:post, /api.elevenlabs.io/)
      .to_return(status: 200, body: 'fake_mp3_bytes', headers: { 'Content-Type' => 'audio/mpeg' })
  end

  describe '#convert' do
    subject(:result) { described_class.convert(agent, 'Olá, como posso ajudar?') }

    it 'inclui output_format=mp3_44100_128 na query string' do
      result
      expect(WebMock).to have_requested(:post, /output_format=mp3_44100_128/)
    end

    it 'envia voice_settings com style, use_speaker_boost e speed' do
      result
      expect(WebMock).to have_requested(:post, /api.elevenlabs.io/).with { |req|
        body = JSON.parse(req.body)
        vs   = body['voice_settings']
        vs['style'] == 0.0 &&
          vs['use_speaker_boost'] == true &&
          vs['speed'] == 1.2 &&
          vs['stability'] == 0.5 &&
          vs['similarity_boost'] == 0.7
      }
    end

    it 'retorna os bytes do MP3' do
      expect(result).to eq('fake_mp3_bytes')
    end

    context 'quando API retorna erro' do
      before { stub_request(:post, /api.elevenlabs.io/).to_return(status: 401) }

      it 'retorna nil' do
        expect(result).to be_nil
      end
    end
  end
end

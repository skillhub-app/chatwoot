class AiAgent::MessageHumanizer
  CHARS_PER_SECOND = 20
  MIN_DELAY        = 1
  MAX_DELAY        = 5

  def self.send_response(conversation, text, agent: nil, agent_user: nil, last_was_audio: false)
    new(conversation, text, agent: agent, agent_user: agent_user, last_was_audio: last_was_audio).send_response
  end

  def initialize(conversation, text, agent: nil, agent_user: nil, last_was_audio: false)
    @conversation   = conversation
    @text           = text.to_s.strip
    @agent          = agent
    @agent_user     = agent_user
    @last_was_audio = last_was_audio
  end

  def send_response
    if should_respond_with_audio?
      audio_sent = send_audio
      fallback_to_text unless audio_sent
    else
      send_text_chunks
    end
  end

  private

  def should_respond_with_audio?
    return false unless @agent&.tts_enabled?
    return false unless @agent.tts_voice_id.present?
    return false unless @agent.tts_api_key_encrypted.present?
    # v67: respostas com URL vão SEMPRE como texto (TTS leria o link literalmente).
    return false if AiAgent::ContentInspector.contains_url?(@text)

    @last_was_audio
  end

  def send_audio
    audio_data = AiAgent::TtsService.convert(@agent, @text)
    return false unless audio_data

    # v69: mensagem + anexo numa única transação. O after_create_commit (que
    # enfileira o SendReplyJob) só dispara após o COMMIT final, com o áudio já
    # persistido — eliminando a race que mandava text.body: nil ao Meta (HTTP 400).
    ActiveRecord::Base.transaction do
      message = create_audio_message!
      attach_audio!(message, audio_data)
    end

    true
  rescue StandardError => e
    Rails.logger.error "[AiAgent] Audio send error: #{e.message}"
    false
  end

  def create_audio_message!
    @conversation.messages.create!(
      account:      @conversation.account,
      inbox:        @conversation.inbox,
      message_type: :outgoing,
      content_type: :text,
      content:      nil,
      private:      false,
      sender:       @agent_user
    )
  end

  def attach_audio!(message, audio_data)
    message.attachments.create!(
      account_id: @conversation.account_id,
      file_type:  :audio,
      file: {
        io:           StringIO.new(audio_data),
        filename:     'resposta.mp3',
        content_type: 'audio/mpeg'
      }
    )
  end

  def fallback_to_text
    Rails.logger.warn '[AiAgent] TTS failed, sending text fallback'
    send_text_chunks
  end

  def send_text_chunks
    chunks = split_into_chunks(@text)
    chunks.each_with_index do |chunk, i|
      sleep(typing_delay(chunk)) if i.positive?
      send_chunk(chunk)
    end
  end

  def split_into_chunks(text)
    chunk_size = @agent&.message_chunk_size.to_i
    chunk_size = 300 if chunk_size < 50

    paragraphs = text.split(/\n{2,}/).map(&:strip).reject(&:blank?)
    return [text] unless paragraphs.size > 1

    result = []
    buffer = ''
    paragraphs.each do |para|
      if buffer.empty?
        buffer = para
      elsif (buffer.length + para.length) < chunk_size
        buffer = "#{buffer}\n\n#{para}"
      else
        result << buffer
        buffer = para
      end
    end
    result << buffer unless buffer.empty?
    result
  end

  def typing_delay(chunk)
    (chunk.length.to_f / CHARS_PER_SECOND).clamp(MIN_DELAY, MAX_DELAY)
  end

  def send_chunk(content)
    @conversation.messages.create!(
      account:      @conversation.account,
      inbox:        @conversation.inbox,
      message_type: :outgoing,
      content_type: :text,
      content:      content,
      private:      false,
      sender:       @agent_user
    )
  end
end

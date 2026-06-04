class AiAgent::IncomingMessageProcessor
  def self.call(message)
    new(message).call
  rescue StandardError => e
    Rails.logger.error "[AiAgent] IncomingMessageProcessor error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
  end

  def initialize(message)
    @message      = message
    @conversation = message.conversation
    @inbox        = message.inbox
  end

  def call
    return unless eligible?

    buffer = AiAgent::MessageBuffer.new(@conversation.id, @agent.message_buffer_seconds)
    buffer.push(message_content)

    return unless buffer.acquire_lock

    AiAgent::ProcessMessageJob.set(wait: @agent.message_buffer_seconds.seconds)
                              .perform_later(@agent.id, @conversation.id)
  end

  private

  def eligible?
    return false unless @message.incoming?
    return false if @message.private?
    return false if @message.content_type == 'activity'
    return false if message_content.blank?
    return false if audio_pending_transcription?
    return false if @conversation.label_list.include?('ia_desligada')

    @agent = ::AiAgent.find_by(inbox: @inbox, active: true)
    return false unless @agent

    ai_conv = find_or_create_ai_conversation
    ai_conv.state == 'active'
  end

  def find_or_create_ai_conversation
    AiAgentConversation.find_or_create_by!(
      ai_agent:     @agent,
      conversation: @conversation
    ) do |c|
      c.contact = @conversation.contact
      c.state   = 'active'
    end
  end

  def message_content
    @message_content ||= extract_message_content(@message)
  end

  def extract_message_content(message)
    base       = message.content.to_s.strip
    audio_text = extract_audio_transcription(message)

    if audio_text.present?
      base.present? ? "#{base}\n\n[Áudio]: #{audio_text}" : "[Áudio]: #{audio_text}"
    else
      base
    end
  end

  def extract_audio_transcription(message)
    message.attachments
           .where(file_type: :audio)
           .filter_map { |att| att.meta&.dig('transcribed_text') }
           .join(' ')
  end

  # Returns true when the message has an audio attachment whose transcription
  # hasn't been written yet AND the account has audio transcription enabled.
  # In that case we block processing here and let AudioTranscriptionService
  # re-call IncomingMessageProcessor once Whisper finishes.
  def audio_pending_transcription?
    return false unless @message.account.audio_transcriptions.present?

    @message.attachments
            .where(file_type: :audio)
            .any? { |att| att.meta&.dig('transcribed_text').blank? }
  end
end

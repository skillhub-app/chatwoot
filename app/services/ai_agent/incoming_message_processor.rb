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
    return false if ai_attachment_pending?

    @agent = ::AiAgent.find_by(inbox: @inbox, active: true)
    return false unless @agent

    # Fonte de verdade única = ai_agent_conversation.state (mesmo portão do
    # ProcessMessageJob). A label ia_desligada é apenas reflexo do state, mantida
    # em sync pelo controller e pelo pause_ai_on_human_response.
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
    parts = []
    base  = message.content.to_s.strip
    parts << base if base.present?

    audio_text = extract_audio_transcription(message)
    parts << "[Áudio]: #{audio_text}" if audio_text.present?

    image_text = extract_attachment_descriptions(message, :image, 'image_description', 'Imagem')
    parts << image_text if image_text.present?

    pdf_text = extract_attachment_descriptions(message, :file, 'pdf_text', 'Documento')
    parts << pdf_text if pdf_text.present?

    parts.join("\n\n")
  end

  def extract_audio_transcription(message)
    message.attachments
           .where(file_type: :audio)
           .filter_map { |att| att.meta&.dig('transcribed_text') }
           .join(' ')
  end

  def extract_attachment_descriptions(message, type, meta_key, label)
    atts = message.attachments.where(file_type: type)
    return nil if atts.empty?

    atts.filter_map do |att|
      value = att.meta&.dig(meta_key)
      if value.present?
        "[#{label}]: #{value}"
      elsif att.meta&.dig('ai_analyzed')
        "[#{label} enviado mas não foi possível processar o conteúdo]"
      end
    end.join("\n\n").presence
  end

  # Bloqueia o processamento enquanto imagem/PDF ainda não foram analisados
  # (espelha audio_pending_transcription?). O AttachmentAnalyzerJob seta
  # ai_analyzed (mesmo em falha) e re-chama este processor.
  def ai_attachment_pending?
    @message.attachments
            .where(file_type: %i[image file])
            .any? { |att| !att.meta&.dig('ai_analyzed') }
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

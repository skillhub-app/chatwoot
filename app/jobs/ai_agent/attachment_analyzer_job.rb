# Analisa um anexo (imagem/PDF) e grava o resultado em attachment.meta, espelhando
# o pipeline do áudio (Whisper). Sempre marca meta['ai_analyzed']=true (mesmo em
# falha) pra não travar o agente, e re-dispara o IncomingMessageProcessor pra que
# a IA processe a mensagem agora que a análise está pronta.
class AiAgent::AttachmentAnalyzerJob < ApplicationJob
  queue_as :ai_agent
  sidekiq_options retry: 1

  def perform(attachment_id)
    attachment = Attachment.find_by(id: attachment_id)
    return unless attachment

    analyze(attachment)
    reprocess(attachment)
  end

  private

  def analyze(attachment)
    service = AiAgent::AttachmentAnalyzerService.new
    case attachment.file_type.to_sym
    when :image
      store(attachment, 'image_description', service.analyze_image(attachment))
    when :file
      store(attachment, 'pdf_text', service.analyze_pdf(attachment))
    else
      mark_analyzed(attachment)
    end
  rescue StandardError => e
    Rails.logger.error "[AiAgent::AttachmentAnalyzerJob] att=#{attachment.id}: #{e.class}: #{e.message}"
    mark_analyzed(attachment)
  end

  def store(attachment, key, value)
    meta = (attachment.meta || {}).merge('ai_analyzed' => true)
    meta[key] = value if value.present?
    attachment.update!(meta: meta)
  end

  def mark_analyzed(attachment)
    attachment.update!(meta: (attachment.meta || {}).merge('ai_analyzed' => true))
  rescue StandardError => e
    Rails.logger.warn "[AiAgent::AttachmentAnalyzerJob] mark_analyzed falhou (att=#{attachment&.id}): #{e.message}"
  end

  def reprocess(attachment)
    return unless attachment.message

    AiAgent::IncomingMessageProcessor.call(attachment.message)
  end
end

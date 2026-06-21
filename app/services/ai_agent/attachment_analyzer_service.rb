# Analisa anexos (imagem e PDF) pra IA "ver"/"ler" o conteúdo.
#
# Provider: OpenAI (mesma chave do Whisper — InstallationConfig CAPTAIN_OPEN_AI_API_KEY).
# - Imagem: gpt-4.1-nano (multimodal) -> descrição textual.
# - PDF curto (<2000 chars): texto puro extraído (pdf-reader).
# - PDF longo: resumo via gpt-4.1-mini.
#
# Tudo graceful: qualquer falha retorna nil (o job marca ai_analyzed e a mensagem segue).
class AiAgent::AttachmentAnalyzerService
  IMAGE_MODEL             = 'gpt-4.1-nano'.freeze
  PDF_SUMMARY_MODEL       = 'gpt-4.1-mini'.freeze
  MAX_BYTES               = 10 * 1024 * 1024
  PDF_TEXT_LIMIT          = 2000
  PDF_SUMMARY_INPUT_LIMIT = 12_000

  IMAGE_SYSTEM = 'Descreva esta imagem para uso por outro agente de atendimento. ' \
                 'Capture o sentimento, o contexto e os detalhes relevantes. Seja objetivo e não invente.'.freeze
  PDF_SYSTEM   = 'Resuma o texto a seguir em um único parágrafo, objetivo e claro, ' \
                 'capturando apenas as informações relevantes.'.freeze

  def analyze_image(attachment)
    return nil if oversized?(attachment)

    mime = attachment.file.blob.content_type.presence || 'image/jpeg'
    b64  = Base64.strict_encode64(attachment.file.download)

    chat(IMAGE_MODEL, [
           { role: 'system', content: IMAGE_SYSTEM },
           { role: 'user', content: [
             { type: 'text', text: 'Descreva a imagem em português.' },
             { type: 'image_url', image_url: { url: "data:#{mime};base64,#{b64}" } }
           ] }
         ])
  end

  # PDF apenas (pdf-reader não lê DOC/DOCX/scaneado -> retorna nil graceful).
  def analyze_pdf(attachment)
    return nil if oversized?(attachment)

    text = extract_pdf_text(attachment).to_s.strip
    return nil if text.blank?
    return text if text.length < PDF_TEXT_LIMIT

    chat(PDF_SUMMARY_MODEL, [
           { role: 'system', content: PDF_SYSTEM },
           { role: 'user', content: text[0, PDF_SUMMARY_INPUT_LIMIT] }
         ]) || text[0, PDF_TEXT_LIMIT]
  end

  private

  def extract_pdf_text(attachment)
    reader = PDF::Reader.new(StringIO.new(attachment.file.download))
    reader.pages.map(&:text).join("\n")
  rescue StandardError => e
    # PDF criptografado, malformado, DOC/DOCX, scaneado sem texto, etc.
    Rails.logger.warn "[AttachmentAnalyzer] PDF não extraível (att=#{attachment.id}): #{e.class}: #{e.message}"
    nil
  end

  def chat(model, messages)
    return nil unless client

    response = client.chat(parameters: { model: model, messages: messages, max_tokens: 500, temperature: 0.3 })
    response.dig('choices', 0, 'message', 'content')&.strip.presence
  end

  def oversized?(attachment)
    size = attachment.file.blob.byte_size
    return false unless size && size > MAX_BYTES

    Rails.logger.warn "[AttachmentAnalyzer] anexo #{attachment.id} > 10MB (#{size} bytes) — pulando análise"
    true
  end

  def client
    @client ||= begin
      key = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value
      if key.blank?
        Rails.logger.warn '[AttachmentAnalyzer] CAPTAIN_OPEN_AI_API_KEY não configurada — análise desativada'
        nil
      else
        base = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value.presence || 'https://api.openai.com/'
        OpenAI::Client.new(access_token: key, uri_base: base)
      end
    end
  end
end

# frozen_string_literal: true

# Sprint v67 — detector de URL no conteúdo de resposta da IA.
#
# Usado pelo MessageHumanizer para FORÇAR envio em texto quando a resposta contém
# um link (Instagram, Google Meet, ZapSign, YouTube, etc.). Em modo voz o TTS
# (ElevenLabs) leria a URL caractere a caractere ("agápeagás dois pontos barra
# barra..."), gerando áudio inútil para o lead.
module AiAgent::ContentInspector
  # E-mails são removidos ANTES da checagem de URL para não dispararem o padrão de
  # domínio (ex.: "maria@example.com" NÃO deve contar como URL).
  EMAIL_PATTERN = /[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}/i

  URL_PATTERNS = [
    %r{https?://[^\s]+}i,                                              # http(s)://...
    %r{www\.[^\s]+\.[a-z]{2,}}i,                                      # www.exemplo.com
    %r{[a-z0-9-]+\.(?:com|com\.br|net|org|io|app|me|co|tv|gov\.br)\b}i # exemplo.com
  ].freeze

  module_function

  def contains_url?(text)
    return false if text.blank?

    sanitized = text.to_s.gsub(EMAIL_PATTERN, ' ')
    URL_PATTERNS.any? { |pattern| sanitized.match?(pattern) }
  end
end

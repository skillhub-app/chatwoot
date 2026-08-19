# frozen_string_literal: true

# Sprint v66 — blindagem definitiva (Fix A) contra vazamento de scaffold.
#
# O follow-up automático do Kanban (Kanban::ExecuteActionService#generate_ai_message)
# monta um prompt com seções de contexto/instrução. O LLM (Gemini Flash Lite)
# ocasionalmente ECOA esse scaffold na resposta — ex.: "(Aguardando resposta da
# cliente)", "Sua tarefa: gerar o follow-up", cabeçalhos "## ..." e separadores "---"
# — que então iam VERBATIM para o WhatsApp do lead (bug confirmado nas conversas
# 676 e 644).
#
# Este sanitizer roda SEMPRE sobre a saída, antes do envio. É defesa em
# profundidade: independe do modelo e do prompt (Fix B reduz a frequência na
# origem; este garante que, se ainda vazar, não chega ao lead).
class AiAgent::FollowUpOutputSanitizer
  # Linhas inteiras de scaffold/meta que nunca devem ir ao lead.
  SCAFFOLD_LINE_PATTERNS = [
    /^\s*\*?\s*sua tarefa\b.*$/i,                 # "Sua tarefa: ...", "*Sua tarefa...*"
    /^\s*\(?\s*aguardando\s+resposta.*$/i,        # "(Aguardando resposta da cliente)"
    /^\s*##\s+.*$/,                               # qualquer "## Header" (markdown)
    /^\s*-{3,}\s*$/,                              # separadores "---"
    /^\s*\*?\s*exemplo de mensagem\b.*$/i,        # "## Exemplo de mensagem:"
    /^\s*\*?\s*contexto (?:da conversa|recente)\b.*$/i, # "## Contexto da conversa"
    /^\s*\*?\s*instru[cç][aã]o\b.*$/i,            # "## Instrução:" / "Instrução do operador"
    %r{^\s*</?[a-z_]+>\s*$}i                      # tags XML soltas (<instrucao>, </contexto_recente>...)
  ].freeze

  # WhatsApp não renderiza markdown — removemos os caracteres de formatação.
  MARKDOWN_CHARS = /[*_#`]/

  def self.call(raw_text)
    new(raw_text).call
  end

  def initialize(raw_text)
    @text = raw_text.to_s
  end

  def call
    drop_everything_before_last_task_header
    strip_scaffold_lines
    strip_markdown
    normalize_whitespace
  end

  private

  # Quando o LLM ecoa a linha "Sua tarefa ...", a mensagem real ao lead costuma vir
  # logo DEPOIS. Cortamos tudo até (e incluindo) a última ocorrência dessa linha.
  def drop_everything_before_last_task_header
    return unless @text.match?(/sua tarefa/i)

    parts = @text.split(/^\s*\*?\s*sua tarefa\b.*$/i)
    @text = parts.last.to_s if parts.size > 1
  end

  def strip_scaffold_lines
    SCAFFOLD_LINE_PATTERNS.each { |pattern| @text = @text.gsub(pattern, '') }
  end

  def strip_markdown
    @text = @text.gsub(MARKDOWN_CHARS, '')
  end

  def normalize_whitespace
    @text.gsub(/[ \t]+\n/, "\n").gsub(/\n{3,}/, "\n\n").strip
  end
end

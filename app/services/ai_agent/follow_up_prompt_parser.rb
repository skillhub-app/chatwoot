# frozen_string_literal: true

class AiAgent::FollowUpPromptParser
  COMMAND_VERBS = %w[
    analise gere pergunte verifique identifique crie faça
    resuma compreenda entenda baseie use considere reflita
    responda escreva monte elabore detalhe explique retome
    descubra avalie examine investigue
  ].freeze

  COMMAND_PREFIXES = [
    /\Acom\s+base\s+n/i,
    /\Acom\s+base\s+em/i,
    /\Aa\s+partir\s+d/i,
    /\Aconsiderando\s+/i
  ].freeze

  attr_reader :input, :contact, :conversation, :stage, :mode_override

  # mode_override: nil = auto-detect, 'template' = force template, 'command' = force command
  def initialize(input, contact:, conversation:, stage: nil, mode_override: nil)
    @input         = input.to_s
    @contact       = contact
    @conversation  = conversation
    @stage         = stage
    @mode_override = mode_override
  end

  def call
    interpolated = interpolate_variables(@input)
    if detected_mode(interpolated) == :command
      build_command_prompt(interpolated)
    else
      build_template_prompt(interpolated)
    end
  end

  def detected_mode(text = @input)
    return @mode_override.to_sym if %w[template command].include?(@mode_override.to_s)

    command?(text) ? :command : :template
  end

  private

  def command?(text)
    return false if text.blank?

    first_word = text.strip.split(/\s+/).first.to_s.downcase.gsub(/[^[:alpha:]]/, '')
    return true if COMMAND_VERBS.include?(first_word)

    COMMAND_PREFIXES.any? { |re| text.match?(re) }
  end

  def interpolate_variables(text)
    text
      .gsub(/\{\{nome\}\}|\[nome\]/i, contact&.name.to_s)
      .gsub(/\{\{telefone\}\}|\[telefone\]/i, contact&.phone_number.to_s)
      .gsub(/\{\{etapa\}\}|\[etapa\]/i, stage&.name.to_s)
  end

  # v66 (Fix B): usamos delimitadores XML em vez de cabeçalhos "## ..." e damos
  # regras de saída explícitas. Tags XML são muito menos propensas a serem ecoadas
  # pelo modelo do que títulos markdown, reduzindo o vazamento de scaffold na origem.
  def build_template_prompt(template)
    <<~PROMPT
      <exemplo_de_mensagem>
      #{template}
      </exemplo_de_mensagem>

      <contexto_recente>
      #{recent_messages_text}
      </contexto_recente>

      <instrucao>
      Gere UMA mensagem de follow-up natural baseada no exemplo e no contexto acima.

      REGRAS CRÍTICAS de saída:
      - Retorne APENAS o texto da mensagem final ao lead
      - NÃO copie esta instrução nem os títulos/tags acima
      - NÃO use markdown (asteriscos, hashtags, traços, sublinhados, crases)
      - NÃO use parênteses metacomentando seu raciocínio (ex.: "(aguardando resposta)")
      - NÃO repita as tags XML acima
      - Comece DIRETO pela saudação ao lead
      - Tom natural e humano
      </instrucao>
    PROMPT
  end

  def build_command_prompt(command)
    <<~PROMPT
      <instrucao_operador>
      #{command}
      </instrucao_operador>

      <contexto_recente>
      #{recent_messages_text}
      </contexto_recente>

      <instrucao>
      Cumpra a instrução do operador acima gerando UMA mensagem de WhatsApp
      apropriada ao estado atual da conversa.

      REGRAS CRÍTICAS de saída:
      - Retorne APENAS o texto da mensagem final ao lead
      - NÃO copie esta instrução nem os títulos/tags acima
      - NÃO use markdown (asteriscos, hashtags, traços, sublinhados, crases)
      - NÃO use parênteses metacomentando seu raciocínio
      - NÃO repita as tags XML acima
      - Comece DIRETO pela mensagem ao lead
      - Tom natural e humano
      </instrucao>
    PROMPT
  end

  def recent_messages_text
    return '' unless conversation

    conversation.messages
                .where(message_type: %i[incoming outgoing])
                .reorder(created_at: :desc)
                .limit(20)
                .reverse
                .filter_map do |m|
                  text = m.content.to_s.strip
                  next if text.blank?

                  speaker = m.message_type == 'incoming' ? 'Cliente' : 'Atendente'
                  "#{speaker}: #{text}"
                end
                .join("\n")
  end
end

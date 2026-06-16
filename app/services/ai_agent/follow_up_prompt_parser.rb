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

  def build_template_prompt(template)
    <<~PROMPT
      Use o seguinte modelo como EXEMPLO de tom e estilo, mas adapte
      ao contexto da conversa abaixo. Gere uma versão personalizada
      e única (não copie literalmente):

      ## Exemplo de mensagem:
      #{template}

      ## Contexto da conversa (últimas 20 mensagens):
      #{recent_messages_text}

      ## Sua tarefa:
      Gere uma mensagem similar ao exemplo, mas personalizada ao
      momento atual da conversa. Mantenha o tom e propósito do exemplo.
    PROMPT
  end

  def build_command_prompt(command)
    <<~PROMPT
      Siga a instrução abaixo considerando o contexto da conversa:

      ## Instrução:
      #{command}

      ## Contexto da conversa (últimas 20 mensagens):
      #{recent_messages_text}

      ## Sua tarefa:
      Cumpra a instrução acima gerando uma mensagem WhatsApp
      apropriada ao estado atual da conversa.
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

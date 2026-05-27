class AiAgent::ConversationSummaryService
  MESSAGES_LIMIT = 50

  def self.call(agent, conversation)
    new(agent, conversation).call
  end

  def initialize(agent, conversation)
    @agent        = agent
    @conversation = conversation
  end

  def call
    history = build_history
    return 'Lead não interagiu — sem mensagens para resumir.' if history.empty?

    response = AiAgent::LlmService.call(
      @agent,
      { system: build_system_prompt, messages: history },
      tools: []
    )

    return nil if response.text.blank?

    response.text.strip.first(2000)
  rescue StandardError => e
    Rails.logger.error "[SummaryAI] Failed to generate summary for conversation #{@conversation.id}: #{e.message}"
    nil
  end

  private

  def build_history
    @conversation.messages
                 .where(message_type: %i[incoming outgoing])
                 .where(private: false)
                 .where.not(content_type: :activity)
                 .order(:created_at)
                 .last(MESSAGES_LIMIT)
                 .filter_map do |msg|
                   next if msg.content.blank?

                   { role: msg.message_type == 'incoming' ? 'user' : 'assistant', content: msg.content }
                 end
  end

  def build_system_prompt
    <<~PROMPT.strip
      Você é um assistente que resume conversas de atendimento ao cliente.

      Sua tarefa: gerar um RESUMO objetivo e neutro da conversa abaixo, em português brasileiro, com no máximo 5 linhas.

      O resumo deve conter:
      - Motivo do contato do lead
      - Pontos principais discutidos
      - Status atual do atendimento
      - Próximos passos (se aplicável)

      NÃO inclua:
      - Suposições ou interpretações pessoais
      - Markdown ou formatação especial
      - Saudações ou despedidas

      Se a conversa estiver vazia ou o lead não tiver respondido, indique isso de forma objetiva.

      Retorne APENAS o texto do resumo, sem prefixos tipo "Resumo:" ou "Resposta:".
    PROMPT
  end
end

# Cria activity messages (mensagens de sistema no centro da conversa) para
# mudanças de estado da IA, reusando o mesmo pipeline das Automation Rules
# nativas (Conversations::ActivityMessageJob).
#
# Graceful: nunca levanta — uma falha aqui não pode quebrar o toggle nem o fluxo
# de resposta humana.
class AiAgent::ActivityService
  def self.ai_enabled(conversation, by: nil)
    log(conversation, by.present? ? "IA ativada por #{by}" : 'IA ativada')
  end

  def self.ai_disabled(conversation, by: nil)
    log(conversation, by.present? ? "IA desativada por #{by}" : 'IA desativada')
  end

  def self.ai_auto_paused(conversation)
    log(conversation, 'IA pausada automaticamente (resposta humana)')
  end

  def self.ai_error(conversation)
    log(conversation, 'Erro ao processar mensagem, um colega foi avisado')
  end

  def self.log(conversation, content)
    return if conversation.blank? || content.blank?

    ::Conversations::ActivityMessageJob.perform_later(
      conversation,
      {
        account_id:   conversation.account_id,
        inbox_id:     conversation.inbox_id,
        message_type: :activity,
        content:      content
      }
    )
  rescue StandardError => e
    Rails.logger.error "[AiAgent::ActivityService] #{e.class}: #{e.message}"
  end
end

# bug F: 2.795 invalid_grant sem nenhum alerta em 1h no incidente de 05/08 —
# o refresh token da conta ficou morto e ninguém percebeu até a investigação
# manual. Conta as falhas por agente numa janela de 1h e, ao cruzar o
# threshold, emite um warning específico e grepável uma única vez por janela
# (debounce), em vez de logar silenciosamente a cada tentativa.
class AiAgent::GoogleCalendar::InvalidGrantMonitor
  THRESHOLD       = 100
  COUNT_WINDOW    = 1.hour
  ALERT_DEBOUNCE  = 1.hour

  def self.track!(agent)
    return unless agent

    count = increment_count(agent.id)
    return if count < THRESHOLD
    return if already_alerted?(agent.id)

    mark_alerted(agent.id)
    Rails.logger.warn(
      "[AiAgent][GoogleCalendar] OAuth needs re-authorization for agent " \
      "#{agent.name} (id=#{agent.id}, account=#{agent.account_id}) — " \
      "#{count} invalid_grant errors in the last hour"
    )
  end

  def self.increment_count(agent_id)
    key = count_key(agent_id)
    Rails.cache.increment(key, 1, expires_in: COUNT_WINDOW) || begin
      Rails.cache.write(key, 1, expires_in: COUNT_WINDOW)
      1
    end
  end
  private_class_method :increment_count

  def self.already_alerted?(agent_id)
    Rails.cache.read(alert_key(agent_id)).present?
  end
  private_class_method :already_alerted?

  def self.mark_alerted(agent_id)
    Rails.cache.write(alert_key(agent_id), true, expires_in: ALERT_DEBOUNCE)
  end
  private_class_method :mark_alerted

  def self.count_key(agent_id)
    "google_calendar:invalid_grant_count:#{agent_id}"
  end
  private_class_method :count_key

  def self.alert_key(agent_id)
    "google_calendar:invalid_grant_alerted:#{agent_id}"
  end
  private_class_method :alert_key
end

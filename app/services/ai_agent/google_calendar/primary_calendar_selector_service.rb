# Após o OAuth do Google Calendar salvar os tokens no AiAgentSchedule, este
# service busca a calendarList do usuário e grava a agenda "primary" (ou a
# primeira disponível) em google_calendar_id — assim google_connected? passa a
# ser true sem exigir um seletor de agenda na UI (provisório).
#
# Graceful degradation: qualquer falha (token, rede, API) é logada e o método
# retorna nil. Nunca levanta exception — não pode bloquear a conexão OAuth.
class AiAgent::GoogleCalendar::PrimaryCalendarSelectorService
  def initialize(schedule)
    @schedule = schedule
  end

  def call
    return if @schedule.google_calendar_id.present?
    return if @schedule.google_refresh_token_encrypted.blank?

    primary = fetch_primary_calendar
    return unless primary

    @schedule.update!(google_calendar_id: primary['id'])
    Rails.logger.info "[GoogleCalendarPrimary] set #{primary['id']} for schedule #{@schedule.id}"
    primary['id']
  rescue StandardError => e
    Rails.logger.error "[GoogleCalendarPrimary] error schedule #{@schedule.id}: #{e.class}: #{e.message}"
    nil
  end

  private

  # Reutiliza o ApiClient existente (que já cuida do refresh do access_token).
  def fetch_primary_calendar
    data  = AiAgent::GoogleCalendar::ApiClient.new(@schedule).calendar_list
    items = Array(data['items'])
    items.find { |c| c['primary'] } || items.first
  end
end

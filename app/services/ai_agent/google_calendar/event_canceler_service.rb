# Tool nativa: cancelar_agendamento.
#
# Recebe APENAS lead_phone (derivado do _context server-side). Busca eventos
# FUTUROS cujo extendedProperties.private.lead_phone == lead_phone e cancela.
#
# Privacidade/segurança:
# - NUNCA aceita event_id como input.
# - NUNCA cancela evento sem extendedProperties.private.lead_phone batendo
#   (re-checagem em código, além do filtro server-side privateExtendedProperty).
# - 0 encontrados -> erro; 1 -> cancela; >1 -> cancela todos do lead + contagem.
class AiAgent::GoogleCalendar::EventCancelerService
  NOT_FOUND = 'Nenhum agendamento encontrado pra esse lead'.freeze

  def initialize(schedule, lead_phone:)
    @schedule   = schedule
    @lead_phone = lead_phone
  end

  # Output: { cancelled_count:, status: } ou { cancelled_count: 0, status:, erro: }
  def call
    return not_found if @lead_phone.blank?

    client = AiAgent::GoogleCalendar::ApiClient.new(@schedule)
    events = matching_future_events(client)
    return not_found if events.empty?

    cancelled = 0
    events.each do |event|
      client.delete_event(@schedule.google_calendar_id, event['id'])
      cancelled += 1
      Rails.logger.info "[AiAgent] EventCanceler cancelou event=#{event['id']} " \
                        "lead=#{masked_phone} schedule=#{@schedule.id}"
    end

    { cancelled_count: cancelled, status: 'cancelled' }
  rescue StandardError => e
    Rails.logger.error "[AiAgent] EventCancelerService error schedule=#{@schedule.id}: #{e.message}"
    { cancelled_count: 0, status: 'error', erro: 'Não consegui cancelar agora. Tente novamente em instantes.' }
  end

  private

  def matching_future_events(client)
    data = client.list_events_by_private_property(
      @schedule.google_calendar_id, 'lead_phone', @lead_phone, time_min: Time.current
    )
    # Defesa em profundidade: re-checa o lead_phone no extendedProperties.private,
    # mesmo o filtro já tendo sido aplicado no servidor do Google.
    Array(data['items']).select do |event|
      event.dig('extendedProperties', 'private', 'lead_phone') == @lead_phone.to_s
    end
  end

  def masked_phone
    p = @lead_phone.to_s
    return p if p.length <= 4

    "#{p[0..2]}***#{p[-2..]}"
  end

  def not_found
    { cancelled_count: 0, status: 'not_found', erro: NOT_FOUND }
  end
end

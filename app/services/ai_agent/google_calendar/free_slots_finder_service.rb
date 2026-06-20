# Tool nativa: consultar_horarios_livres.
#
# Retorna APENAS slots LIVRES dentro de [data_inicio, data_fim], com a duração
# pedida. Privacidade: usa só o Freebusy (períodos ocupados), NUNCA lista
# eventos — não há como vazar título/participante/id de terceiros aqui.
class AiAgent::GoogleCalendar::FreeSlotsFinderService
  include AiAgent::GoogleCalendar::SlotGeneration

  MAX_SLOTS = 20

  def initialize(schedule, data_inicio:, data_fim:, duracao: nil)
    @schedule    = schedule
    @data_inicio = data_inicio
    @data_fim    = data_fim
    @duracao     = duracao
  end

  # Output: [{ inicio_iso:, fim_iso:, duracao_min: }, ...]
  def call
    return [] unless @schedule.google_connected?

    tz_name    = @schedule.ai_agent.timezone
    now        = Time.current.in_time_zone(tz_name)
    min_notice = now + @schedule.min_notice_minutes.minutes

    start_time = [parse_in_zone(@data_inicio, tz_name), min_notice].compact.max
    end_time   = parse_in_zone(@data_fim, tz_name)
    return [] if start_time.blank? || end_time.blank? || end_time <= start_time

    duration = (@duracao.presence || @schedule.slot_duration_minutes).to_i

    client = AiAgent::GoogleCalendar::ApiClient.new(@schedule)
    busy   = fetch_busy_times(client, @schedule.google_calendar_id, start_time, end_time)

    build_free_slots(start_time, end_time, duration, busy, @schedule, max_slots: MAX_SLOTS).map do |slot|
      { inicio_iso: slot[:start].iso8601, fim_iso: slot[:end].iso8601, duracao_min: duration }
    end
  rescue StandardError => e
    Rails.logger.error "[AiAgent] FreeSlotsFinderService error: #{e.message}"
    []
  end

  private

  def parse_in_zone(value, tz_name)
    return nil if value.blank?

    Time.find_zone(tz_name).parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end

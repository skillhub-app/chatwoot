# Lógica compartilhada de geração de slots livres a partir de busy times do
# Google Freebusy + janelas semanais (weekly_windows) do schedule.
#
# Usado por AiAgent::GoogleCalendar::SlotsFinder (slots pro prompt/UI) e por
# AiAgent::GoogleCalendar::FreeSlotsFinderService (tool nativa).
#
# IMPORTANTE (privacidade): só lida com PERÍODOS OCUPADOS (busy), nunca com
# títulos/participantes/ids de eventos. O Freebusy não retorna esses dados.
module AiAgent::GoogleCalendar::SlotGeneration
  private

  def fetch_busy_times(client, calendar_id, min_time, max_time)
    data = client.freebusy(calendar_id, min_time, max_time)
    Array(data.dig('calendars', calendar_id, 'busy')).map do |period|
      { start: Time.parse(period['start']), end: Time.parse(period['end']) }
    end
  end

  # Gera slots de 30 em 30 min dentro de [min_time, max_time], com a duração
  # pedida, respeitando weekly_windows e evitando busy_times. Para em max_slots
  # (nil = sem limite).
  def build_free_slots(min_time, max_time, duration_minutes, busy_times, schedule, max_slots: nil)
    slots    = []
    duration = duration_minutes.to_i.minutes
    cursor   = min_time.beginning_of_hour + (min_time.min < 30 ? 0 : 30).minutes
    cursor  += 30.minutes while cursor < min_time

    while cursor < max_time && (max_slots.nil? || slots.size < max_slots)
      slot_end = cursor + duration
      weekday  = AiAgentSchedule::WEEKDAYS[cursor.wday]
      windows  = schedule.windows_for(weekday)

      if within_windows?(cursor, slot_end, windows) && !overlaps_busy?(cursor, slot_end, busy_times)
        slots << { start: cursor, end: slot_end }
      end

      cursor += 30.minutes
    end

    slots
  end

  def within_windows?(slot_start, slot_end, windows)
    windows.any? do |w|
      window_start = parse_time_of_day(slot_start.to_date, w['start'], slot_start.time_zone)
      window_end   = parse_time_of_day(slot_start.to_date, w['end'],   slot_start.time_zone)
      slot_start >= window_start && slot_end <= window_end
    end
  end

  def overlaps_busy?(slot_start, slot_end, busy_times)
    busy_times.any? do |b|
      slot_start < b[:end] && slot_end > b[:start]
    end
  end

  def parse_time_of_day(date, time_str, tz)
    h, m = time_str.to_s.split(':').map(&:to_i)
    tz.local(date.year, date.month, date.day, h, m)
  end
end

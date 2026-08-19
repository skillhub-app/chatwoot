class AiAgent::GoogleCalendar::SlotsFinder
  include AiAgent::GoogleCalendar::SlotGeneration

  MAX_SLOTS = 10

  def self.find(schedule, days: nil)
    new(schedule, days: days).find
  end

  def initialize(schedule, days: nil)
    @schedule = schedule
    @days     = days || schedule.max_days_in_advance
  end

  def find
    return [] unless @schedule.google_connected?

    client    = AiAgent::GoogleCalendar::ApiClient.new(@schedule)
    time_zone = @schedule.ai_agent.timezone
    now       = Time.current.in_time_zone(time_zone)
    min_time  = now + @schedule.min_notice_minutes.minutes
    max_time  = now + @days.days

    busy_times = fetch_busy_times(client, @schedule.google_calendar_id, min_time, max_time)
    build_free_slots(min_time, max_time, @schedule.slot_duration_minutes, busy_times, @schedule, max_slots: MAX_SLOTS)
  rescue StandardError => e
    Rails.logger.error "[AiAgent] SlotsFinder error: #{e.message}"
    []
  end
end

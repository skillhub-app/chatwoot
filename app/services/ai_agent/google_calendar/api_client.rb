class AiAgent::GoogleCalendar::ApiClient
  BASE_URL = 'https://www.googleapis.com/calendar/v3'

  def initialize(schedule)
    @schedule = schedule
    ensure_valid_token!
  end

  def freebusy(calendar_id, time_min, time_max)
    post('freeBusy', {
           timeMin: time_min.iso8601,
           timeMax: time_max.iso8601,
           items:   [{ id: calendar_id }]
         })
  end

  def create_event(calendar_id, event_body, query = {})
    post("calendars/#{CGI.escape(calendar_id)}/events", event_body, query)
  end

  def list_events(calendar_id, time_min, time_max)
    get("calendars/#{CGI.escape(calendar_id)}/events", {
          timeMin:      time_min.iso8601,
          timeMax:      time_max.iso8601,
          singleEvents: true,
          orderBy:      'startTime'
        })
  end

  def calendar_list(max_results: 100)
    get('users/me/calendarList', { maxResults: max_results })
  end

  # Lista eventos filtrados por extendedProperties.private.<key> = <value>, via o
  # parâmetro privateExtendedProperty da API do Google (filtro server-side). Usado
  # pra achar APENAS eventos criados pela IA pra um lead específico — nunca varre
  # a agenda inteira nem expõe eventos de terceiros.
  def list_events_by_private_property(calendar_id, key, value, time_min: nil)
    get("calendars/#{CGI.escape(calendar_id)}/events", {
          privateExtendedProperty: "#{key}=#{value}",
          singleEvents:            true,
          orderBy:                 'startTime',
          maxResults:              250,
          timeMin:                 time_min&.iso8601
        }.compact)
  end

  def delete_event(calendar_id, event_id)
    delete("calendars/#{CGI.escape(calendar_id)}/events/#{CGI.escape(event_id)}")
  end

  private

  def ensure_valid_token!
    return unless @schedule.token_expired?

    token_data = AiAgent::GoogleCalendar::AuthService.refresh_token(
      @schedule.google_refresh_token_encrypted
    )
    @schedule.update_columns(
      google_access_token_encrypted: token_data['access_token'],
      google_token_expires_at:       Time.current + token_data['expires_in'].to_i.seconds
    )
  end

  def access_token
    @schedule.google_access_token_encrypted
  end

  def conn
    @conn ||= Faraday.new(url: BASE_URL) do |f|
      f.request :json
      f.response :json
      f.options.timeout = 30
    end
  end

  def get(path, params = {})
    response = conn.get(path) do |req|
      req.headers['Authorization'] = "Bearer #{access_token}"
      req.params = params
    end
    raise "Google Calendar API error: #{response.body}" unless response.success?

    response.body
  end

  def post(path, body, query = {})
    response = conn.post(path) do |req|
      req.headers['Authorization'] = "Bearer #{access_token}"
      req.params = query if query.present?
      req.body = body
    end
    raise "Google Calendar API error: #{response.body}" unless response.success?

    response.body
  end

  def delete(path)
    response = conn.delete(path) do |req|
      req.headers['Authorization'] = "Bearer #{access_token}"
    end
    # DELETE de evento no Google retorna 204 No Content (sem body) em sucesso.
    raise "Google Calendar API error: #{response.body}" unless response.success?

    response.body
  end
end

# Tool nativa: criar_agendamento.
#
# Cria um evento no calendário do agente com proteções de privacidade:
# - visibility: 'private'
# - extendedProperties.private.{lead_phone, conversation_id, created_by}
#   (lead_phone é a CHAVE usada depois pra cancelar com segurança)
# - attendee = o lead, SOMENTE se tiver e-mail; sem e-mail, o telefone vai na
#   descrição pra equipe humana saber como contatar.
#
# lead_phone/conversation_id chegam do _context (server-side), NUNCA do input do LLM.
class AiAgent::GoogleCalendar::EventCreatorService
  def initialize(schedule, data_hora_inicio:, lead_phone:, ai_agent_id:,
                 titulo: nil, descricao: nil, conversation_id: nil, contact_email: nil)
    @schedule         = schedule
    @data_hora_inicio = data_hora_inicio
    @lead_phone       = lead_phone
    @ai_agent_id      = ai_agent_id
    @titulo           = titulo
    @descricao        = descricao
    @conversation_id  = conversation_id
    @contact_email    = contact_email
  end

  # Output: { event_id:, html_link:, status:, start:, end: } ou { status: 'error', erro: ... }
  def call
    tz_name = @schedule.ai_agent.timezone
    start_t = Time.find_zone(tz_name).parse(@data_hora_inicio.to_s)
    return error('Data/hora inválida') if start_t.blank?

    end_t  = start_t + @schedule.slot_duration_minutes.minutes
    result = AiAgent::GoogleCalendar::ApiClient.new(@schedule)
                                              .create_event(@schedule.google_calendar_id, build_event(start_t, end_t, tz_name))

    {
      event_id:  result['id'],
      html_link: result['htmlLink'],
      start:     start_t.iso8601,
      end:       end_t.iso8601,
      status:    'created'
    }
  rescue StandardError => e
    Rails.logger.error "[AiAgent] EventCreatorService error schedule=#{@schedule.id}: #{e.message}"
    error('Não consegui criar o agendamento agora. Tente novamente em instantes.')
  end

  private

  def build_event(start_t, end_t, tz_name)
    event = {
      summary:     @titulo.presence || @schedule.default_subject.presence || 'Reunião',
      description: description_text,
      start:       { dateTime: start_t.iso8601, timeZone: tz_name },
      end:         { dateTime: end_t.iso8601,   timeZone: tz_name },
      visibility:  'private',
      extendedProperties: {
        private: {
          lead_phone:      @lead_phone.to_s,
          conversation_id: @conversation_id.to_s,
          created_by:      "ai_agent_#{@ai_agent_id}"
        }
      }
    }
    event[:attendees] = [{ email: @contact_email }] if @contact_email.present?
    event.compact
  end

  def description_text
    parts = []
    parts << @descricao if @descricao.present?
    # Sem e-mail não dá pra convidar o lead no Google; deixa o telefone pra equipe humana.
    parts << "Telefone contato: #{@lead_phone}" if @contact_email.blank? && @lead_phone.present?
    parts.join("\n").presence
  end

  def error(message)
    { status: 'error', erro: message }
  end
end

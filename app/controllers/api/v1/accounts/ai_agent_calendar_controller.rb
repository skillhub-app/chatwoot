# Endpoints internos das tools nativas de Google Calendar.
#
# NÃO usam autenticação de usuário: são chamados server-to-server pelo
# AiAgent::ToolExecutor, autenticados por um token interno (ENV INTERNAL_API_TOKEN)
# enviado no header X-Internal-Token (interpolado em runtime a partir de
# tool.headers => { 'X-Internal-Token' => '${INTERNAL_API_TOKEN}' }).
#
# Privacidade (regras de ouro da sprint):
# - lead_phone vem SEMPRE do _context (contact_id) — NUNCA do input do LLM.
# - Nenhum endpoint retorna eventos de terceiros.
# - lead_phone/conversation_id/contact_id são devolvidos só em _audit (output_result),
#   nunca no texto que volta pro LLM (isso é controlado pelo response_template da tool).
class Api::V1::Accounts::AiAgentCalendarController < Api::BaseController
  # Substitui a auth padrão por validação de token interno.
  skip_before_action :authenticate_access_token!, raise: false
  skip_before_action :validate_bot_access_token!, raise: false
  skip_before_action :authenticate_user!,         raise: false

  before_action :authenticate_internal_request!
  before_action :load_account_and_agent
  before_action :require_context

  def consultar_horarios_livres
    slots = AiAgent::GoogleCalendar::FreeSlotsFinderService.new(
      @schedule,
      data_inicio: params[:data_inicio],
      data_fim:    params[:data_fim],
      duracao:     params[:duracao_minutos]
    ).call

    render json: { slots: slots, total: slots.size }
  end

  def criar_agendamento
    phone = lead_phone
    return render_no_lead if phone.blank?

    result = AiAgent::GoogleCalendar::EventCreatorService.new(
      @schedule,
      data_hora_inicio: params[:data_hora_inicio],
      titulo:           params[:titulo],
      descricao:        params[:descricao],
      lead_phone:       phone,
      conversation_id:  context_conversation_id,
      ai_agent_id:      @agent.id,
      contact_email:    @contact&.email
    ).call

    # 'mensagem' é o ÚNICO campo que o response_template expõe ao LLM (sem PII).
    # event_id/html_link/_audit ficam só no output_result (auditoria).
    render json: result.merge(mensagem: create_message(result), _audit: audit_payload(phone))
  end

  def cancelar_agendamento
    phone = lead_phone
    return render_no_lead if phone.blank?

    result = AiAgent::GoogleCalendar::EventCancelerService.new(@schedule, lead_phone: phone).call

    render json: result.merge(mensagem: cancel_message(result), _audit: audit_payload(phone))
  end

  private

  def authenticate_internal_request!
    provided = request.headers['X-Internal-Token'].to_s
    expected = ENV.fetch('INTERNAL_API_TOKEN', '').to_s
    return if secure_token_match?(provided, expected)

    render json: { error: 'unauthorized' }, status: :unauthorized
  end

  def secure_token_match?(provided, expected)
    return false if provided.blank? || expected.blank?

    ActiveSupport::SecurityUtils.secure_compare(
      OpenSSL::Digest::SHA256.hexdigest(provided),
      OpenSSL::Digest::SHA256.hexdigest(expected)
    )
  end

  def load_account_and_agent
    account = Account.find_by(id: params[:account_id])
    @agent  = account&.ai_agents&.find_by(id: params[:ai_agent_id])
    # Multi-tenant: agent inexistente ou de outra account => 403.
    return render json: { error: 'forbidden' }, status: :forbidden if @agent.blank?

    @schedule = @agent.ai_agent_schedule
    return render json: { error: 'calendar_not_connected' }, status: :unprocessable_entity unless @schedule&.google_connected?
  end

  def require_context
    return render json: { error: 'missing _context' }, status: :bad_request if params[:_context].blank?

    @contact = Account.find_by(id: params[:account_id])
                      &.contacts&.find_by(id: context_contact_id) if context_contact_id.present?
  end

  # lead_phone é SEMPRE derivado do contato do _context, nunca aceito como input.
  def lead_phone
    @contact&.phone_number
  end

  def context_contact_id
    params.dig(:_context, :contact_id)
  end

  def context_conversation_id
    params.dig(:_context, :conversation_id)
  end

  # Textos legíveis pro LLM — sem telefone, sem event_id, sem extendedProperties.
  def create_message(result)
    return result[:erro] if result[:status] != 'created'

    when_label = (Time.zone.parse(result[:start].to_s).strftime('%d/%m às %H:%M') if result[:start].present?)
    when_label ? "Reunião agendada com sucesso para #{when_label}." : 'Reunião agendada com sucesso.'
  rescue ArgumentError, TypeError
    'Reunião agendada com sucesso.'
  end

  def cancel_message(result)
    case result[:status]
    when 'cancelled' then "#{result[:cancelled_count]} agendamento(s) cancelado(s) com sucesso."
    else result[:erro] || 'Não foi possível cancelar o agendamento.'
    end
  end

  def audit_payload(phone)
    {
      lead_phone:      phone,
      conversation_id: context_conversation_id,
      contact_id:      context_contact_id
    }
  end

  def render_no_lead
    render json: { status: 'error', erro: 'Lead sem telefone no contexto da conversa' }, status: :unprocessable_entity
  end
end

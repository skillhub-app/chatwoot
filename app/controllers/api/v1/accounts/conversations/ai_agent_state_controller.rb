class Api::V1::Accounts::Conversations::AiAgentStateController < Api::V1::Accounts::BaseController
  MANUALLY_SETTABLE_STATES = %w[active paused].freeze

  before_action :set_conversation
  before_action :set_ai_conv

  def show
    render json: ai_conv_json(@ai_conv)
  end

  def update
    state = params[:state].to_s
    unless MANUALLY_SETTABLE_STATES.include?(state)
      return render json: { error: "State '#{state}' cannot be set manually. Allowed: #{MANUALLY_SETTABLE_STATES.join(', ')}" },
                    status: :unprocessable_entity
    end

    changed = @ai_conv.state != state
    @ai_conv.update!(state: state, paused_reason: state == 'active' ? nil : 'manual')
    sync_labels(state) # sempre — garante a etiqueta correta (idempotente)
    emit_activity(state) if changed # activity só na mudança real (sem duplicar)
    render json: ai_conv_json(@ai_conv)
  end

  def reactivate
    changed = @ai_conv.state != 'active'
    @ai_conv.update!(state: 'active', paused_reason: nil)
    sync_labels('active')
    emit_activity('active') if changed
    render json: ai_conv_json(@ai_conv)
  end

  private

  def set_conversation
    # O frontend envia o display_id (convenção dos demais controllers de conversa).
    # Usar .find (por PK) só funcionava quando id == display_id (conta única).
    @conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id])
  end

  def set_ai_conv
    @ai_conv = AiAgentConversation.find_by(conversation: @conversation)
    render json: { error: 'No AI agent conversation found' }, status: :not_found unless @ai_conv
  end

  # Garantia ABSOLUTA e idempotente: state=active => ia_ligada (sem ia_desligada);
  # state=paused => ia_desligada (sem ia_ligada). Set atômico, não baseado em
  # transição — chamar N vezes não duplica nem deixa as duas etiquetas juntas.
  def sync_labels(state)
    labels = @conversation.label_list.to_a
    labels = if state == 'active'
               (labels - ['ia_desligada']) | ['ia_ligada']
             else
               (labels - ['ia_ligada']) | ['ia_desligada']
             end
    @conversation.update!(label_list: labels)
  rescue StandardError => e
    Rails.logger.warn "[AiAgentState] sync_labels falhou: #{e.message}"
  end

  def emit_activity(state)
    by = Current.user&.name
    if state == 'active'
      AiAgent::ActivityService.ai_enabled(@conversation, by: by)
    else
      AiAgent::ActivityService.ai_disabled(@conversation, by: by)
    end
  end

  def ai_conv_json(ai_conv)
    {
      id:              ai_conv.id,
      state:           ai_conv.state,
      paused_reason:   ai_conv.paused_reason,
      ai_agent_id:     ai_conv.ai_agent_id,
      conversation_id: ai_conv.conversation_id,
      updated_at:      ai_conv.updated_at
    }
  end
end

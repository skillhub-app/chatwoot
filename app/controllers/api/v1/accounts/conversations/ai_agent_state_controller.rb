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

    @ai_conv.update!(state: state, paused_reason: state == 'active' ? nil : 'manual')
    sync_labels(state)
    render json: ai_conv_json(@ai_conv)
  end

  def reactivate
    @ai_conv.update!(state: 'active', paused_reason: nil)
    sync_labels('active')
    render json: ai_conv_json(@ai_conv)
  end

  private

  def set_conversation
    @conversation = Current.account.conversations.find(params[:conversation_id])
  end

  def set_ai_conv
    @ai_conv = AiAgentConversation.find_by(conversation: @conversation)
    render json: { error: 'No AI agent conversation found' }, status: :not_found unless @ai_conv
  end

  def sync_labels(state)
    if state == 'active'
      remove_label('ia_desligada')
      add_label('ia_ligada')
    else
      remove_label('ia_ligada')
      add_label('ia_desligada')
    end
  end

  def add_label(label)
    @conversation.labels.push(label) unless @conversation.label_list.include?(label)
  rescue StandardError => e
    Rails.logger.warn "[AiAgentState] Could not add label '#{label}': #{e.message}"
  end

  def remove_label(label)
    return unless @conversation.label_list.include?(label)

    @conversation.labels = @conversation.label_list - [label]
  rescue StandardError => e
    Rails.logger.warn "[AiAgentState] Could not remove label '#{label}': #{e.message}"
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

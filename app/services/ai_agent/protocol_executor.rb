class AiAgent::ProtocolExecutor
  def self.execute(protocol, conversation, agent, summary_text: nil)
    new(protocol, conversation, agent, summary_text: summary_text).execute
  end

  def initialize(protocol, conversation, agent, summary_text: nil)
    @protocol     = protocol
    @conversation = conversation
    @agent        = agent
    @summary_text = summary_text
  end

  def execute
    apply_action
    add_label
    send_summary if @protocol.auto_summarize && @summary_text.present?
    notify_phone if @protocol.phone_number.present?
  end

  private

  def apply_action
    @ai_conv = AiAgentConversation.find_by(ai_agent: @agent, conversation: @conversation)
    return unless @ai_conv

    case @protocol.action
    when 'continue'
      # IA segue respondendo — nenhuma alteração de state
    when 'pause_for_human'
      @ai_conv.update!(state: 'transferred', paused_reason: "protocol:#{@protocol.protocol_type}")
      sync_labels_for_state(@ai_conv)
    when 'end_conversation'
      @ai_conv.update!(state: 'ended', paused_reason: "protocol:#{@protocol.protocol_type}")
      sync_labels_for_state(@ai_conv)
      add_label_safe(@conversation, 'atendimento_encerrado')
    when 'pause_temporary'
      @ai_conv.update!(state: 'paused', paused_reason: 'protocol_temporary')
      sync_labels_for_state(@ai_conv)
    end
  end

  def sync_labels_for_state(ai_conv)
    if ai_conv.state == 'active'
      remove_label(@conversation, 'ia_desligada')
      add_label_safe(@conversation, 'ia_ligada')
    else
      remove_label(@conversation, 'ia_ligada')
      add_label_safe(@conversation, 'ia_desligada')
    end
  end

  def add_label
    label = "ia-#{@protocol.protocol_type}"
    add_label_safe(@conversation, label)
  end

  def add_label_safe(conversation, label)
    conversation.labels.push(label) unless conversation.label_list.include?(label)
  rescue StandardError => e
    Rails.logger.warn "[AiAgent] Could not add label '#{label}': #{e.message}"
  end

  def remove_label(conversation, label)
    return unless conversation.label_list.include?(label)

    conversation.labels = conversation.label_list - [label]
  rescue StandardError => e
    Rails.logger.warn "[AiAgent] Could not remove label '#{label}': #{e.message}"
  end

  def send_summary
    @conversation.messages.create!(
      account:      @conversation.account,
      inbox:        @conversation.inbox,
      message_type: :outgoing,
      content_type: :text,
      content:      "📋 *Resumo do atendimento IA:*\n#{@summary_text}",
      private:      true
    )

    kanban_item = KanbanItem.find_by(conversation_id: @conversation.id)
    return unless kanban_item

    kanban_item.kanban_notes.create!(
      content: "📋 Resumo do atendimento IA:\n#{@summary_text}",
      author:  @conversation.account.users.first
    )
  rescue StandardError => e
    Rails.logger.error "[ProtocolExecutor] Failed to save summary: #{e.message}"
  end

  def notify_phone
    return if @protocol.phone_number.blank?
    return if @summary_text.blank?

    AiAgent::ProtocolNotificationService.call(
      phone:   @protocol.phone_number,
      summary: @summary_text,
      account: @conversation.account
    )
  rescue StandardError => e
    Rails.logger.error "[ProtocolExecutor] notify_phone failed: #{e.message}"
  end
end

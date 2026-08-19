class KanbanListener < BaseListener
  include Singleton

  def conversation_created(event)
    conversation = event.data[:conversation]
    return unless conversation

    Kanban::ConversationEventService.new(conversation, 'conversation_created').perform
  rescue StandardError => e
    Rails.logger.error "KanbanListener#conversation_created error: #{e.message}"
  end

  def message_created(event)
    message = event.data[:message]
    return unless message&.conversation

    Kanban::ConversationEventService.new(message.conversation, 'message_created').perform
  rescue StandardError => e
    Rails.logger.error "KanbanListener#message_created error: #{e.message}"
  end
end

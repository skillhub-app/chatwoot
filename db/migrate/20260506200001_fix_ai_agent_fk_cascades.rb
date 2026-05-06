class FixAiAgentFkCascades < ActiveRecord::Migration[7.1]
  def change
    # ai_agent_conversations.contact_id → SET NULL when contact is deleted
    remove_foreign_key :ai_agent_conversations, column: :contact_id
    add_foreign_key    :ai_agent_conversations, :contacts, column: :contact_id, on_delete: :nullify

    # ai_agent_conversations.conversation_id → CASCADE when conversation is deleted
    remove_foreign_key :ai_agent_conversations, column: :conversation_id
    add_foreign_key    :ai_agent_conversations, :conversations, column: :conversation_id, on_delete: :cascade

    # ai_agent_executions.conversation_id → CASCADE when conversation is deleted
    remove_foreign_key :ai_agent_executions, column: :conversation_id
    add_foreign_key    :ai_agent_executions, :conversations, column: :conversation_id, on_delete: :cascade
  end
end

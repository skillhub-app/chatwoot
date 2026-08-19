class AddMemoryWindowToAiAgents < ActiveRecord::Migration[7.1]
  def change
    add_column :ai_agents, :memory_window_messages, :integer, default: 100, null: false
    add_index  :ai_agent_executions, [:conversation_id, :created_at],
               name: 'index_ai_agent_executions_on_conv_created_at'
  end
end

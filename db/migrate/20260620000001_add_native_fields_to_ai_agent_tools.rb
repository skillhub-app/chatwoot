class AddNativeFieldsToAiAgentTools < ActiveRecord::Migration[7.1]
  def change
    add_column :ai_agent_tools, :is_native, :boolean, default: false, null: false
    add_column :ai_agent_tools, :native_key, :string
    add_index  :ai_agent_tools, :native_key
  end
end

class AddActionToAiAgentProtocols < ActiveRecord::Migration[7.1]
  def change
    add_column :ai_agent_protocols, :action, :string, default: 'pause_for_human', null: false
    add_index  :ai_agent_protocols, :action
  end
end

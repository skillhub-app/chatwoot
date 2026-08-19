class AddStopOnAiDisabledToKanbanAutomations < ActiveRecord::Migration[7.1]
  def change
    add_column :kanban_automations, :stop_on_ai_disabled, :boolean, default: false, null: false
  end
end

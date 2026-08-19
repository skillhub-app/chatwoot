# frozen_string_literal: true

class AddStageEnteredAtToKanbanItems < ActiveRecord::Migration[7.0]
  def up
    add_column :kanban_items, :stage_entered_at, :datetime
    add_index :kanban_items, %i[stage_id stage_entered_at]
    # Existing cards: NULL intentional (no badge shown until next stage move)
  end

  def down
    remove_index :kanban_items, %i[stage_id stage_entered_at]
    remove_column :kanban_items, :stage_entered_at
  end
end

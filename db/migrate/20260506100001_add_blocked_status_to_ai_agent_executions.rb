class AddBlockedStatusToAiAgentExecutions < ActiveRecord::Migration[7.1]
  def up
    # status is a plain string column with inclusion validation in the model
    # no DB-level enum — nothing to change at DB level.
    # The model constant STATUSES is updated in the model file directly.
    # This migration exists as a record of the intentional schema change.
  end

  def down
    # no-op
  end
end

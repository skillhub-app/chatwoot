class BackfillEditedOnCaptainAssistantResponses < ActiveRecord::Migration[7.0]
  def up
    # rubocop:disable Rails/SkipsModelValidations
    Captain::AssistantResponse
      .where('updated_at - created_at > interval ?', '15 days')
      .update_all(edited: true)
    # rubocop:enable Rails/SkipsModelValidations
  end

  def down
    # rubocop:disable Rails/SkipsModelValidations
    Captain::AssistantResponse.where(edited: true).update_all(edited: false)
    # rubocop:enable Rails/SkipsModelValidations
  end
end

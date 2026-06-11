class CleanupLegacyDiegoAgent < ActiveRecord::Migration[7.0]
  def up
    return unless table_exists?(:ai_agents)

    agent = AiAgent.find_by(id: 1, name: 'diego')
    return if agent.blank?

    Rails.logger.info '[Cleanup] Deleting legacy agent diego (id=1)'
    agent.destroy
  end

  def down
    # Sem rollback - diego não volta
  end
end

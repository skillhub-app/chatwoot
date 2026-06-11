class MigrateExistingLlmKeys < ActiveRecord::Migration[7.0]
  def up
    return unless table_exists?(:ai_agents)

    AiAgent.where.not(llm_api_key_encrypted: [nil, ''])
           .order(updated_at: :desc)
           .group_by { |a| [a.account_id, a.llm_provider] }
           .each do |(account_id, provider), agents|
      # llm_api_key_encrypted é plain text em produção (nome engana)
      unique_keys = agents.map(&:llm_api_key_encrypted).uniq
      if unique_keys.size > 1
        Rails.logger.warn(
          "[MigrateExistingLlmKeys] Conflict: account=#{account_id} provider=#{provider} " \
          "has #{unique_keys.size} different keys. Using most recent (agent id=#{agents.first.id})."
        )
      end

      credential = LlmProviderCredential.find_or_initialize_by(
        account_id: account_id,
        provider: provider
      )
      credential.api_key = agents.first.llm_api_key_encrypted
      credential.save!

      AiAgent.where(account_id: account_id, llm_provider: provider)
             .update_all(llm_credential_id: credential.id)
    end
  end

  def down
    AiAgent.update_all(llm_credential_id: nil)
  end
end

class GoogleCalendarCallbacksController < ApplicationController
  skip_before_action :authenticate_user!, raise: false
  skip_before_action :verify_authenticity_token, raise: false

  def callback
    code  = params[:code]
    state = params[:state].to_s

    agent_id, account_id = state.split(':')

    if agent_id.blank? || account_id.blank? || code.blank?
      Rails.logger.error "[GoogleCalendar] Invalid callback params: state=#{state.inspect} code_present=#{code.present?}"
      return redirect_to error_url(account_id), allow_other_host: true
    end

    account = Account.find_by(id: account_id)
    agent   = account&.ai_agents&.find_by(id: agent_id)

    if agent.blank?
      Rails.logger.error "[GoogleCalendar] Agent not found: agent_id=#{agent_id} account_id=#{account_id}"
      return redirect_to error_url(account_id), allow_other_host: true
    end

    redirect_uri = "#{frontend_url}/google_calendar/callback"
    token_data   = AiAgent::GoogleCalendar::AuthService.exchange_code(code, redirect_uri)

    if token_data.blank? || token_data['access_token'].blank?
      Rails.logger.error "[GoogleCalendar] Exchange code failed: agent_id=#{agent_id}"
      return redirect_to error_url(account_id, agent_id), allow_other_host: true
    end

    schedule = agent.ai_agent_schedule || agent.build_ai_agent_schedule
    schedule.update!(
      google_refresh_token_encrypted: token_data['refresh_token'],
      google_access_token_encrypted:  token_data['access_token'],
      google_token_expires_at:        Time.current + token_data['expires_in'].to_i.seconds
    )

    # Auto-seleciona a primary calendar (graceful: nunca bloqueia a conexão).
    AiAgent::GoogleCalendar::PrimaryCalendarSelectorService.new(schedule).call

    # Se a agenda ficou conectada de verdade, cadastra as tools nativas de
    # calendário no agente (graceful: nunca bloqueia a conexão).
    activate_native_tools(schedule)

    Rails.logger.info "[GoogleCalendar] Connected agent_id=#{agent_id} account_id=#{account_id}"
    redirect_to success_url(account_id, agent_id), allow_other_host: true
  rescue StandardError => e
    Rails.logger.error "[GoogleCalendar] Callback error: #{e.class}: #{e.message}"
    Rails.logger.error e.backtrace.first(10).join("\n")
    redirect_to error_url(account_id, agent_id), allow_other_host: true
  end

  private

  def activate_native_tools(schedule)
    return unless schedule.google_connected?

    AiAgent::NativeToolRegistry.activate(schedule.ai_agent, 'google_calendar')
  rescue StandardError => e
    Rails.logger.error "[GoogleCalendar] Native tools activation failed: #{e.class}: #{e.message}"
  end

  def frontend_url
    ENV.fetch('FRONTEND_URL', 'http://localhost:3000')
  end

  def success_url(account_id, agent_id)
    "#{frontend_url}/app/accounts/#{account_id}/settings/ai-agents/#{agent_id}?calendar=connected"
  end

  def error_url(account_id, agent_id = nil)
    base = "#{frontend_url}/app/accounts/#{account_id}/settings/ai-agents"
    base = "#{base}/#{agent_id}" if agent_id.present?
    "#{base}?calendar=error"
  end
end

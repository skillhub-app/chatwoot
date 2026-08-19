# Feature C: cascade de resiliência em cima do AiAgent::LlmService.
#
# 1. Chama o provider configurado no agente (na prática, Gemini).
# 2. Erro transitório (5xx/429/timeout/conexão) → retry com backoff curto
#    (2s, depois 5s) — até 3 tentativas no total no provider original.
# 3. Se ainda falhar (ou já era um erro definitivo, sem valor em retentar) e
#    o agente é Gemini → cai pro OpenAI GPT-4.1-mini, usando a mesma
#    credencial do Whisper/Vision (InstallationConfig CAPTAIN_OPEN_AI_API_KEY).
# 4. Se o OpenAI também falhar (ou o agente já não era Gemini pra começo de
#    conversa), sobe o erro original pro chamador — quem trata isso hoje é
#    o rescue de AiAgent::ProcessMessageJob#run (bug A+B: FALLBACK_MESSAGE +
#    activity + label).
class AiAgent::LlmRouterService
  RETRY_DELAYS      = [2, 5].freeze
  FALLBACK_PROVIDER = 'openai'.freeze
  FALLBACK_MODEL    = 'gpt-4.1-mini'.freeze
  TRANSIENT_PATTERN = /\b(50\d|429)\b|UNAVAILABLE|RESOURCE_EXHAUSTED|overloaded|rate.?limit|timeout/i

  def self.call(agent, prompt, tools: [])
    new(agent, prompt, tools: tools).call
  end

  def self.fallback_used_today
    Rails.cache.read("ai_agent:fallback_used_today:#{Date.current}").to_i
  end

  def initialize(agent, prompt, tools: [])
    @agent  = agent
    @prompt = prompt
    @tools  = tools
  end

  def call
    attempt = 0
    begin
      AiAgent::LlmService.call(@agent, @prompt, tools: @tools)
    rescue StandardError => e
      attempt += 1
      if transient_error?(e) && attempt <= RETRY_DELAYS.size
        delay = RETRY_DELAYS[attempt - 1]
        Rails.logger.warn "[AiAgent][LlmRouter] tentativa #{attempt} falhou (#{e.message.to_s.first(200)}) — retry em #{delay}s"
        sleep_before_retry(delay)
        retry
      end

      call_fallback(e)
    end
  end

  private

  def transient_error?(error)
    error.is_a?(Faraday::TimeoutError) ||
      error.is_a?(Faraday::ConnectionFailed) ||
      TRANSIENT_PATTERN.match?(error.message.to_s)
  end

  def call_fallback(original_error)
    raise original_error unless @agent.llm_provider == 'gemini'

    if gemini_specific_history?
      # próximo passo (fora do escopo desta sprint): tradutor de histórico de
      # tool-calls Gemini (`role: 'model', parts: [...]`) pro formato OpenAI
      # (`role: 'assistant', tool_calls: [...]`) antes de liberar o fallback
      # também pra turnos com tool-calls já em andamento.
      Rails.logger.warn '[AiAgent][LlmRouter] histórico já tem turnos formatados pra Gemini — ' \
                         'sem tradutor de tool-calls pro OpenAI ainda, subindo o erro original'
      raise original_error
    end

    Rails.logger.warn "[AiAgent][LlmRouter] Fallback OpenAI acionado por conta de: #{original_error.message.to_s.first(300)}"
    increment_fallback_counter
    AiAgent::LlmService.call(fallback_agent, @prompt, tools: @tools)
  rescue StandardError => e
    Rails.logger.error "[AiAgent][LlmRouter] Fallback OpenAI também falhou: #{e.message}"
    raise
  end

  def gemini_specific_history?
    Array(@prompt[:messages]).any? { |m| m.is_a?(Hash) && (m.key?(:parts) || m[:role] == 'model') }
  end

  def fallback_agent
    dup_agent = @agent.dup
    dup_agent.llm_provider = FALLBACK_PROVIDER
    dup_agent.llm_model    = FALLBACK_MODEL
    key = openai_fallback_key
    dup_agent.define_singleton_method(:effective_api_key) { key }
    dup_agent
  end

  def openai_fallback_key
    InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value
  end

  def increment_fallback_counter
    key = "ai_agent:fallback_used_today:#{Date.current}"
    Rails.cache.increment(key, 1, expires_in: 26.hours) || Rails.cache.write(key, 1, expires_in: 26.hours)
  end

  def sleep_before_retry(seconds)
    sleep(seconds)
  end
end

class AiAgent::ToolExecutor
  Result = Struct.new(:success?, :output, :formatted_for_llm, :http_status, :duration_ms, :error_message, keyword_init: true)

  def initialize(tool, params, context = {})
    @tool    = tool
    @params  = params.is_a?(String) ? JSON.parse(params) : params.to_h
    @context = context.slice(:conversation_id, :contact_id, :account_id).stringify_keys
  end

  def call
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result  = execute_request
    duration = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
    result   = result.merge(duration_ms: duration)

    log_execution(result)

    Result.new(**result)
  rescue StandardError => e
    Rails.logger.error "[AiAgent::ToolExecutor] Unexpected error for tool '#{@tool.name}': #{e.message}"
    fallback = { success?: false, output: {}, formatted_for_llm: "Erro interno ao executar ferramenta: #{e.message}",
                 http_status: nil, duration_ms: 0, error_message: e.message }
    log_execution(fallback)
    Result.new(**fallback)
  end

  private

  def execute_request
    conn = Faraday.new do |f|
      f.request  :json
      f.response :json
      f.options.timeout      = @tool.timeout_seconds
      f.options.open_timeout = [@tool.timeout_seconds, 5].min
    end

    body = build_body

    resp = case @tool.http_method.upcase
           when 'GET'    then conn.get(@tool.endpoint_url)    { |r| apply_headers(r); r.params = body }
           when 'DELETE' then conn.delete(@tool.endpoint_url) { |r| apply_headers(r) }
           else
             conn.public_send(@tool.http_method.downcase, @tool.endpoint_url) do |r|
               apply_headers(r)
               r.body = body
             end
           end

    output = resp.body.is_a?(Hash) ? resp.body : { raw: resp.body.to_s }

    if resp.success?
      { success?: true, output: output, formatted_for_llm: format_output(output),
        http_status: resp.status, duration_ms: 0, error_message: nil }
    else
      msg = "HTTP #{resp.status}: #{output['error'] || output['message'] || resp.body.to_s.truncate(200)}"
      { success?: false, output: output, formatted_for_llm: "Erro ao consultar serviço externo: #{msg}",
        http_status: resp.status, duration_ms: 0, error_message: msg }
    end
  rescue Faraday::TimeoutError
    msg = "Timeout após #{@tool.timeout_seconds}s"
    { success?: false, output: {}, formatted_for_llm: "Erro ao consultar serviço externo: #{msg}",
      http_status: nil, duration_ms: 0, error_message: msg, _timeout: true }
  rescue Faraday::ConnectionFailed => e
    msg = "Falha de conexão: #{e.message}"
    { success?: false, output: {}, formatted_for_llm: "Erro ao consultar serviço externo: #{msg}",
      http_status: nil, duration_ms: 0, error_message: msg }
  end

  def build_body
    base = @params.merge('_context' => @context)

    return base if @tool.request_body_template.blank?

    rendered = render_template(@tool.request_body_template, base)
    begin
      JSON.parse(rendered)
    rescue JSON::ParserError
      Rails.logger.error "[ToolExecutor] template JSON inválido após render para tool='#{@tool.name}'"
      base
    end
  end

  def apply_headers(req)
    req.headers['Content-Type'] = 'application/json'
    (@tool.headers || {}).each { |k, v| req.headers[k] = resolve_env(v.to_s) }
  end

  # Valores no formato EXATO "${NOME}" são resolvidos da ENV em runtime. Permite
  # guardar uma referência a segredo no header da tool (banco) sem o valor real.
  # Qualquer outro valor passa inalterado.
  def resolve_env(value)
    match = value.match(/\A\$\{(\w+)\}\z/)
    match ? ENV.fetch(match[1], '') : value
  end

  def format_output(output)
    return render_template(@tool.response_template, output) if @tool.response_template.present?

    output.to_json
  end

  # Substitui {{ key }} e {{key}} (com ou sem espaços) em qualquer template string.
  # Suporta dot notation: {{ a.b }} faz dig('a', 'b') no hash de vars.
  # Placeholder sem valor correspondente vira "" e gera warning no log.
  def render_template(template, vars)
    template.gsub(/\{\{\s*([\w.]+)\s*\}\}/) do
      path  = $1.split('.')
      # dig por um path quebrado (ex: cavar dentro de um escalar) levanta TypeError;
      # tratamos como ausente (placeholder vira "") em vez de estourar.
      value = begin
        vars.dig(*path)
      rescue TypeError
        nil
      end
      if value.nil?
        Rails.logger.warn "[ToolExecutor] placeholder sem valor: '#{$1}' tool='#{@tool.name}'"
        ''
      else
        value.to_s
      end
    end
  end

  def log_execution(result)
    status = if result[:_timeout]
               'timeout'
             elsif result[:success?]
               'success'
             else
               'error'
             end

    AiAgent::ToolExecution.create!(
      ai_agent:      @tool.ai_agent,
      ai_agent_tool: @tool,
      tool_name:     @tool.name,
      input_params:  @params,
      output_result: result[:output],
      http_status:   result[:http_status],
      status:        status,
      duration_ms:   result[:duration_ms],
      error_message: result[:error_message]
    )
  rescue StandardError => e
    Rails.logger.warn "[AiAgent::ToolExecutor] Could not log execution: #{e.message}"
  end
end

class AiAgent::LlmService
  OPENAI_URL    = 'https://api.openai.com/v1/chat/completions'
  ANTHROPIC_URL = 'https://api.anthropic.com/v1/messages'
  GEMINI_URL    = 'https://generativelanguage.googleapis.com/v1beta/models'

  LlmResponse = Struct.new(:type, :text, :tool_calls, :raw_parts, keyword_init: true) do
    def text? = type == :text
    def tool_calls? = type == :tool_calls
  end

  ToolCall = Struct.new(:id, :name, :arguments, keyword_init: true)

  def self.call(agent, prompt, tools: [])
    new(agent, prompt, tools: tools).call
  end

  def self.format_tool_call_message(provider, tool_call, raw_parts: nil)
    case provider
    when 'anthropic'
      { role: 'assistant', content: [{ type: 'tool_use', id: tool_call.id, name: tool_call.name, input: tool_call.arguments }] }
    when 'gemini'
      parts = raw_parts || [{ functionCall: { name: tool_call.name, args: tool_call.arguments } }]
      if raw_parts&.any? { |p| p['thoughtSignature'].present? }
        Rails.logger.debug "[AiAgent] Gemini thoughtSignature re-sent in model turn message"
      end
      { role: 'model', parts: parts }
    else
      { role: 'assistant', content: nil, tool_calls: [{ id: tool_call.id, type: 'function', function: { name: tool_call.name, arguments: tool_call.arguments.to_json } }] }
    end
  end

  def self.format_tool_result_message(provider, tool_call_id, tool_name, result_text)
    case provider
    when 'anthropic'
      { role: 'user', content: [{ type: 'tool_result', tool_use_id: tool_call_id, content: result_text }] }
    when 'gemini'
      fn_response = { name: tool_name, response: { result: result_text } }
      fn_response[:id] = tool_call_id if tool_call_id.present?
      { role: 'user', parts: [{ functionResponse: fn_response }] }
    else
      { role: 'tool', tool_call_id: tool_call_id, name: tool_name, content: result_text }
    end
  end

  def initialize(agent, prompt, tools: [])
    @agent  = agent
    @prompt = prompt # { system: String, messages: Array }
    @tools  = Array(tools)
  end

  def call
    case @agent.llm_provider
    when 'anthropic' then call_anthropic
    when 'gemini'    then call_gemini
    else call_openai
    end
  end

  private

  def api_key
    @agent.llm_api_key_encrypted.presence || raise(ArgumentError, 'LLM API key not configured')
  end

  def has_tools?
    @tools.any?
  end

  # ── OpenAI ────────────────────────────────────────────────────────────────────

  def call_openai
    messages = [{ role: 'system', content: @prompt[:system] }] + @prompt[:messages]

    conn = Faraday.new(url: OPENAI_URL) do |f|
      f.request :json
      f.response :json
      f.options.timeout = 60
    end

    body = { model: @agent.llm_model, messages: messages, max_tokens: 2000, temperature: 0.7 }
    if has_tools?
      body[:tools] = @tools.map do |t|
        { type: 'function', function: { name: t.name, description: t.full_description, parameters: t.parameters_schema.presence || { type: 'object', properties: {} } } }
      end
      body[:tool_choice] = 'auto'
    end

    response = conn.post do |req|
      req.headers['Authorization'] = "Bearer #{api_key}"
      req.headers['Content-Type']  = 'application/json'
      req.body = body
    end

    raise "OpenAI error: #{response.body}" unless response.success?

    message    = response.body.dig('choices', 0, 'message') || {}
    tool_calls = message['tool_calls']

    if tool_calls.present?
      calls = tool_calls.map do |tc|
        args = tc.dig('function', 'arguments')
        args = begin
                 JSON.parse(args)
               rescue StandardError
                 {}
               end
        ToolCall.new(id: tc['id'], name: tc.dig('function', 'name'), arguments: args)
      end
      LlmResponse.new(type: :tool_calls, text: nil, tool_calls: calls, raw_parts: nil)
    else
      LlmResponse.new(type: :text, text: message['content'].to_s.strip, tool_calls: [], raw_parts: nil)
    end
  end

  # ── Anthropic ────────────────────────────────────────────────────────────────

  def call_anthropic
    conn = Faraday.new(url: ANTHROPIC_URL) do |f|
      f.request :json
      f.response :json
      f.options.timeout = 60
    end

    body = {
      model:      @agent.llm_model,
      system:     @prompt[:system],
      messages:   @prompt[:messages],
      max_tokens: 2000
    }
    if has_tools?
      body[:tools] = @tools.map do |t|
        { name: t.name, description: t.full_description, input_schema: t.parameters_schema.presence || { type: 'object', properties: {} } }
      end
    end

    response = conn.post do |req|
      req.headers['x-api-key']         = api_key
      req.headers['anthropic-version'] = '2023-06-01'
      req.headers['Content-Type']      = 'application/json'
      req.body = body
    end

    raise "Anthropic error: #{response.body}" unless response.success?

    content_blocks = response.body['content'] || []
    tool_use_block = content_blocks.find { |b| b['type'] == 'tool_use' }

    if tool_use_block
      call = ToolCall.new(id: tool_use_block['id'], name: tool_use_block['name'], arguments: tool_use_block['input'] || {})
      LlmResponse.new(type: :tool_calls, text: nil, tool_calls: [call], raw_parts: nil)
    else
      text = content_blocks.find { |b| b['type'] == 'text' }&.dig('text').to_s.strip
      LlmResponse.new(type: :text, text: text, tool_calls: [], raw_parts: nil)
    end
  end

  # ── Gemini ────────────────────────────────────────────────────────────────────

  def call_gemini
    url  = "#{GEMINI_URL}/#{@agent.llm_model}:generateContent"
    conn = Faraday.new do |f|
      f.request :json
      f.response :json
      f.options.timeout = 60
    end

    contents = @prompt[:messages].map do |m|
      # Messages already in Gemini wire format (tool call/result turns) pass through unchanged
      next m if m.key?(:parts)

      role = m[:role] == 'assistant' ? 'model' : 'user'
      { role: role, parts: [{ text: m[:content].to_s }] }
    end

    body = {
      system_instruction: { parts: [{ text: @prompt[:system].to_s }] },
      contents:           contents,
      generationConfig:   { temperature: 0.7, maxOutputTokens: 2000 }
    }
    if has_tools?
      body[:tools] = [{
        function_declarations: @tools.map do |t|
          { name: t.name, description: t.full_description, parameters: t.parameters_schema.presence || { type: 'object', properties: {} } }
        end
      }]
    end

    response = conn.post(url) do |req|
      req.headers['Content-Type'] = 'application/json'
      req.params['key']           = api_key
      req.body = body
    end

    raise "Gemini error: #{response.body}" unless response.success?

    raw_parts = response.body.dig('candidates', 0, 'content', 'parts') || []
    fn_call   = raw_parts.find { |p| p['functionCall'].present? }

    if fn_call
      fc  = fn_call['functionCall']
      id  = fc['id'].presence || SecureRandom.hex(8)
      has_sig = fn_call['thoughtSignature'].present?
      Rails.logger.debug "[AiAgent] Gemini functionCall name=#{fc['name']} id=#{id} thoughtSignature=#{has_sig}"
      Rails.logger.debug "[AiAgent] Gemini thoughtSignature captured (#{fn_call['thoughtSignature'].length} chars)" if has_sig
      call = ToolCall.new(id: id, name: fc['name'], arguments: fc['args'] || {})
      LlmResponse.new(type: :tool_calls, text: nil, tool_calls: [call], raw_parts: raw_parts)
    else
      text = raw_parts.map { |p| p['text'] }.compact.join.strip
      LlmResponse.new(type: :text, text: text, tool_calls: [], raw_parts: nil)
    end
  end

end

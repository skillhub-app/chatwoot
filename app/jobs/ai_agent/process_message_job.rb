class AiAgent::ProcessMessageJob < ApplicationJob
  queue_as :ai_agent
  sidekiq_options retry: 2

  MAX_ITERATIONS    = 5
  FALLBACK_MESSAGE  = 'Estou com dificuldade pra processar agora, um colega vai te chamar em instantes.'

  def perform(agent_id, conversation_id)
    agent        = ::AiAgent.find_by(id: agent_id)
    conversation = Conversation.find_by(id: conversation_id)
    return unless agent && conversation

    buffer       = AiAgent::MessageBuffer.new(conversation_id, agent.message_buffer_seconds)
    new_messages = buffer.pop_all
    buffer.release_lock

    return if new_messages.empty?

    ai_conv = AiAgentConversation.find_by(ai_agent: agent, conversation: conversation)
    return if ai_conv && ai_conv.state != 'active'

    started_at = Time.current
    run(agent, conversation, new_messages, started_at)
  end

  private

  def run(agent, conversation, new_messages, started_at)
    # reorder: Message tem default_scope order(created_at: :asc) que anula .order encadeado
    last_was_audio = conversation.messages
                                 .where(message_type: :incoming)
                                 .reorder(created_at: :desc)
                                 .first
                                 &.attachments
                                 &.where(file_type: :audio)
                                 &.exists? || false

    combined_text = new_messages.join(' ')
    injection     = AiAgent::PromptInjectionFilter.blocked?(combined_text)

    if injection[:blocked]
      duration = ((Time.current - started_at) * 1000).round
      blocked_response = AiAgent::PromptInjectionFilter::BLOCKED_RESPONSE
      record_execution(agent, conversation, new_messages, blocked_response, duration,
                       status: 'blocked',
                       error_message: "prompt_injection: #{injection[:pattern]}")
      AiAgent::MessageHumanizer.send_response(conversation, blocked_response, agent: agent,
                                              last_was_audio: last_was_audio)
      return
    end

    prompt   = AiAgent::PromptBuilder.build(agent, conversation, new_messages)
    active_tools = agent.tools.active.ordered.to_a
    context  = build_context(agent, conversation)

    final_response = agentic_loop(agent, prompt, active_tools, context, started_at, conversation)

    duration = ((Time.current - started_at) * 1000).round

    protocols      = agent.ai_agent_protocols.order(:position)
    protocol       = AiAgent::ProtocolDetector.detect(final_response, protocols)
    clean_response = AiAgent::ProtocolDetector.clean(final_response, protocol)

    booking_result = try_create_booking(agent, conversation, clean_response)
    clean_response = booking_result[:response] if booking_result

    record_execution(agent, conversation, new_messages, final_response, duration,
                     protocol: protocol, status: 'success')

    if protocol
      summary = protocol.auto_summarize ? AiAgent::ConversationSummaryService.call(agent, conversation) : nil
      AiAgent::ProtocolExecutor.execute(protocol, conversation, agent, summary_text: summary)
      AiAgent::MessageHumanizer.send_response(conversation, clean_response, agent: agent,
                                              last_was_audio: last_was_audio) if clean_response.present?
    else
      AiAgent::MessageHumanizer.send_response(conversation, clean_response, agent: agent,
                                              last_was_audio: last_was_audio)
    end

    update_stats(agent, conversation, new_messages.size)
  rescue StandardError => e
    Rails.logger.error "[AiAgent] ProcessMessageJob error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    duration = ((Time.current - started_at) * 1000).round
    record_execution(agent, conversation, new_messages, nil, duration,
                     status: 'error', error_message: e.message)
  end

  # ── Agentic loop ─────────────────────────────────────────────────────────────

  def agentic_loop(agent, prompt, active_tools, context, started_at, conversation)
    messages   = prompt[:messages].dup
    iteration  = 0

    loop do
      iteration += 1

      if iteration > MAX_ITERATIONS
        Rails.logger.error "[AiAgent] MAX_ITERATIONS (#{MAX_ITERATIONS}) exceeded for agent=#{agent.id} conversation=#{conversation.id}"
        record_execution(
          agent, conversation, [], nil,
          ((Time.current - started_at) * 1000).round,
          status: 'error',
          error_message: "MAX_ITERATIONS exceeded after #{MAX_ITERATIONS} loops"
        )
        return FALLBACK_MESSAGE
      end

      current_prompt = { system: prompt[:system], messages: messages }
      response = AiAgent::LlmService.call(agent, current_prompt, tools: active_tools)

      if response.text?
        Rails.logger.info "[AiAgent] Loop done at iteration=#{iteration} agent=#{agent.id}"
        return response.text
      end

      # response.tool_calls? — process each call
      response.tool_calls.each do |tool_call|
        tool = active_tools.find { |t| t.name == tool_call.name }

        messages << AiAgent::LlmService.format_tool_call_message(agent.llm_provider, tool_call, raw_parts: response.raw_parts)

        if tool.nil?
          Rails.logger.warn "[AiAgent] Tool '#{tool_call.name}' not found or inactive for agent=#{agent.id}"
          messages << AiAgent::LlmService.format_tool_result_message(
            agent.llm_provider, tool_call.id, tool_call.name,
            "Erro: ferramenta '#{tool_call.name}' não existe ou está inativa."
          )
          next
        end

        Rails.logger.info "[AiAgent] Executing tool='#{tool.name}' iteration=#{iteration} agent=#{agent.id}"
        result = AiAgent::ToolExecutor.new(tool, tool_call.arguments, context).call
        Rails.logger.info "[AiAgent] Tool='#{tool.name}' status=#{result.success? ? 'success' : 'error'} duration=#{result.duration_ms}ms"

        messages << AiAgent::LlmService.format_tool_result_message(
          agent.llm_provider, tool_call.id, tool_call.name,
          result.formatted_for_llm
        )
      end
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────────────────

  def build_context(agent, conversation)
    {
      account_id:      agent.account_id,
      conversation_id: conversation.id,
      contact_id:      conversation.contact_id
    }
  end

  def try_create_booking(agent, conversation, response_text)
    match = response_text.match(/#AGENDAR\s+([^\s\n]+)/)
    return nil unless match

    datetime_str = match[1]
    schedule     = agent.ai_agent_schedule
    return nil unless schedule&.google_connected?

    contact = conversation.contact
    event   = AiAgent::GoogleCalendar::EventCreator.create(
      schedule, datetime_str,
      contact: contact,
      subject: schedule.default_subject.presence || "Reunião com #{contact&.name || 'cliente'}"
    )

    clean  = response_text.gsub(/#AGENDAR\s+[^\s\n]+/, '').strip
    append = "\n\n✅ Reunião confirmada! #{event[:start].strftime('%A, %d/%m às %H:%M')}.\nLink: #{event[:html_link]}"

    { response: clean + append }
  rescue StandardError => e
    Rails.logger.error "[AiAgent] Booking error: #{e.message}"
    nil
  end

  def record_execution(agent, conversation, new_messages, response, duration,
                       protocol: nil, status: 'success', error_message: nil)
    AiAgentExecution.create!(
      ai_agent:           agent,
      conversation:       conversation,
      input_type:         'text',
      input_content:      new_messages.join("\n"),
      output_content:     response,
      duration_ms:        duration,
      status:             status,
      protocol_triggered: protocol&.keyword,
      error_message:      error_message
    )
  rescue StandardError => e
    Rails.logger.warn "[AiAgent] Could not record execution: #{e.message}"
  end

  def update_stats(agent, conversation, received_count)
    AiAgentConversation.where(ai_agent: agent, conversation: conversation).update_all(
      "messages_received = messages_received + #{received_count}, messages_sent = messages_sent + 1"
    )
  end
end

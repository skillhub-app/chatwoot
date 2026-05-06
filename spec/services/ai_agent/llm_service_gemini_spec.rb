require 'rails_helper'

RSpec.describe AiAgent::LlmService do
  GEMINI_BASE = 'https://generativelanguage.googleapis.com/v1beta/models'

  let(:agent) do
    instance_double(
      'AiAgent',
      llm_provider:          'gemini',
      llm_model:             'gemini-2.0-flash',
      llm_api_key_encrypted: 'test-key'
    )
  end

  let(:base_prompt) do
    { system: 'You are helpful.', messages: [{ role: 'user', content: 'Hello' }] }
  end

  def gemini_url(model = 'gemini-2.0-flash')
    "#{GEMINI_BASE}/#{model}:generateContent?key=test-key"
  end

  def stub_gemini(body, model: 'gemini-2.0-flash', status: 200)
    stub_request(:post, gemini_url(model))
      .to_return(status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  # ─── call (text responses) ────────────────────────────────────────────────

  describe '#call — text response' do
    it 'returns LlmResponse with type :text' do
      stub_gemini({ 'candidates' => [{ 'content' => { 'role' => 'model', 'parts' => [{ 'text' => 'Hi!' }] } }] })

      result = described_class.call(agent, base_prompt)

      expect(result.text?).to be true
      expect(result.text).to eq('Hi!')
      expect(result.raw_parts).to be_nil
    end

    it 'does not break when candidates is empty' do
      stub_gemini({ 'candidates' => [] })

      result = described_class.call(agent, base_prompt)

      expect(result.text?).to be true
      expect(result.text).to eq('')
    end

    it 'does not break when candidates key is missing' do
      stub_gemini({})

      result = described_class.call(agent, base_prompt)

      expect(result.text?).to be true
      expect(result.text).to eq('')
    end
  end

  # ─── Gemini 2.0 — functionCall with real id, no thoughtSignature ──────────

  describe '#call — Gemini 2.0 functionCall with real id' do
    let(:response_body) do
      {
        'candidates' => [{
          'content' => {
            'role'  => 'model',
            'parts' => [{
              'functionCall' => { 'id' => 'real-id-abc', 'name' => 'get_weather', 'args' => { 'city' => 'SP' } }
            }]
          }
        }]
      }
    end

    it 'uses the real id from response, NOT SecureRandom' do
      stub_gemini(response_body)
      allow(SecureRandom).to receive(:hex).and_call_original

      result = described_class.call(agent, base_prompt)

      expect(result.tool_calls?).to be true
      expect(result.tool_calls.first.id).to eq('real-id-abc')
      expect(SecureRandom).not_to have_received(:hex)
    end

    it 'captures raw_parts for preservation in next turn' do
      stub_gemini(response_body)

      result = described_class.call(agent, base_prompt)

      expect(result.raw_parts).to be_an(Array)
      expect(result.raw_parts.first['functionCall']['name']).to eq('get_weather')
    end
  end

  # ─── Gemini 2.0 — functionCall WITHOUT id (legacy model) — fallback ───────

  describe '#call — functionCall without id (legacy/no id)' do
    let(:response_body) do
      {
        'candidates' => [{
          'content' => {
            'role'  => 'model',
            'parts' => [{
              'functionCall' => { 'name' => 'get_weather', 'args' => { 'city' => 'SP' } }
            }]
          }
        }]
      }
    end

    it 'falls back to SecureRandom when id is absent' do
      stub_gemini(response_body)
      allow(SecureRandom).to receive(:hex).with(8).and_return('fallback-id')

      result = described_class.call(agent, base_prompt)

      expect(result.tool_calls.first.id).to eq('fallback-id')
    end
  end

  # ─── Gemini 3 — thoughtSignature captured ────────────────────────────────

  describe '#call — Gemini 3 with thoughtSignature' do
    let(:thought_sig) { 'ENCRYPTED_THOUGHT_SIGNATURE_TOKEN' }
    let(:response_body) do
      {
        'candidates' => [{
          'content' => {
            'role'  => 'model',
            'parts' => [{
              'functionCall'     => { 'id' => 'g3-id-xyz', 'name' => 'check_order', 'args' => { 'order_id' => '42' } },
              'thoughtSignature' => thought_sig
            }]
          }
        }]
      }
    end

    it 'captures thoughtSignature in raw_parts' do
      stub_gemini(response_body, model: 'gemini-2.0-flash')

      result = described_class.call(agent, base_prompt)

      expect(result.raw_parts.first['thoughtSignature']).to eq(thought_sig)
    end

    it 'uses the real id alongside thoughtSignature' do
      stub_gemini(response_body, model: 'gemini-2.0-flash')

      result = described_class.call(agent, base_prompt)

      expect(result.tool_calls.first.id).to eq('g3-id-xyz')
    end
  end

  # ─── format_tool_call_message ─────────────────────────────────────────────

  describe '.format_tool_call_message' do
    let(:tool_call) { AiAgent::LlmService::ToolCall.new(id: 'tc-1', name: 'get_weather', arguments: { 'city' => 'SP' }) }

    context 'without raw_parts (Gemini 2.0 baseline)' do
      it 'reconstructs basic model message' do
        msg = described_class.format_tool_call_message('gemini', tool_call)

        expect(msg[:role]).to eq('model')
        expect(msg[:parts]).to eq([{ functionCall: { name: 'get_weather', args: { 'city' => 'SP' } } }])
      end
    end

    context 'with raw_parts containing thoughtSignature (Gemini 3)' do
      let(:raw_parts) do
        [{ 'functionCall' => { 'id' => 'g3-id', 'name' => 'get_weather', 'args' => { 'city' => 'SP' } },
           'thoughtSignature' => 'SIG_TOKEN' }]
      end

      it 'passes raw_parts through unchanged, preserving thoughtSignature' do
        msg = described_class.format_tool_call_message('gemini', tool_call, raw_parts: raw_parts)

        expect(msg[:role]).to eq('model')
        expect(msg[:parts]).to eq(raw_parts)
        expect(msg[:parts].first['thoughtSignature']).to eq('SIG_TOKEN')
      end
    end

    context 'with raw_parts but no thoughtSignature (Gemini 2.0 with id)' do
      let(:raw_parts) do
        [{ 'functionCall' => { 'id' => 'real-id', 'name' => 'get_weather', 'args' => {} } }]
      end

      it 'still passes raw_parts through' do
        msg = described_class.format_tool_call_message('gemini', tool_call, raw_parts: raw_parts)

        expect(msg[:parts]).to eq(raw_parts)
      end
    end

    context 'for OpenAI (raw_parts ignored)' do
      it 'returns OpenAI-format message unaffected' do
        msg = described_class.format_tool_call_message('openai', tool_call, raw_parts: [{ 'something' => 'irrelevant' }])

        expect(msg[:role]).to eq('assistant')
        expect(msg.key?(:parts)).to be false
      end
    end
  end

  # ─── format_tool_result_message ──────────────────────────────────────────

  describe '.format_tool_result_message' do
    context 'for Gemini' do
      it 'includes id in functionResponse when tool_call_id present' do
        msg = described_class.format_tool_result_message('gemini', 'real-id-abc', 'get_weather', 'Sunny')

        fn = msg[:parts].first[:functionResponse]
        expect(fn[:name]).to eq('get_weather')
        expect(fn[:id]).to eq('real-id-abc')
        expect(fn[:response][:result]).to eq('Sunny')
      end

      it 'uses functionResponse part format' do
        msg = described_class.format_tool_result_message('gemini', 'id1', 'tool', 'result')

        expect(msg[:role]).to eq('user')
        expect(msg[:parts].first.key?(:functionResponse)).to be true
      end
    end

    context 'for OpenAI' do
      it 'uses role: tool format' do
        msg = described_class.format_tool_result_message('openai', 'call-1', 'get_weather', 'Sunny')

        expect(msg[:role]).to eq('tool')
        expect(msg[:content]).to eq('Sunny')
      end
    end
  end

  # ─── Multi-turn: Gemini 2.0 — id preserved across turns ──────────────────

  describe 'multi-turn — Gemini 2.0 id regression test' do
    it 'preserves the real functionCall id in the next-turn contents' do
      # Turn 1: model responds with a functionCall that has a real id
      turn1_response = {
        'candidates' => [{
          'content' => {
            'role'  => 'model',
            'parts' => [{ 'functionCall' => { 'id' => 'real-g2-id', 'name' => 'search', 'args' => { 'q' => 'rails' } } }]
          }
        }]
      }
      stub_gemini(turn1_response)

      result = described_class.call(agent, base_prompt)
      tool_call = result.tool_calls.first

      # Simulate what agentic_loop does: append model msg + tool result
      model_msg  = described_class.format_tool_call_message('gemini', tool_call, raw_parts: result.raw_parts)
      result_msg = described_class.format_tool_result_message('gemini', tool_call.id, tool_call.name, 'Rails 8 docs')

      # The model message preserves the raw functionCall with real id
      expect(model_msg[:parts].first['functionCall']['id']).to eq('real-g2-id')
      # The result message mirrors the same real id
      expect(result_msg[:parts].first[:functionResponse][:id]).to eq('real-g2-id')
    end
  end

  # ─── Multi-turn: Gemini 3 — thoughtSignature + id preserved ──────────────

  describe 'multi-turn — Gemini 3 thoughtSignature + id preserved across turns' do
    it 'round-trips thoughtSignature from turn 1 into turn 2 body' do
      thought_sig = 'BASE64_ENCRYPTED_THOUGHT_TOKEN'

      turn1_body = {
        'candidates' => [{
          'content' => {
            'role'  => 'model',
            'parts' => [{
              'functionCall'     => { 'id' => 'g3-turn1-id', 'name' => 'book_flight', 'args' => { 'from' => 'GRU', 'to' => 'LIS' } },
              'thoughtSignature' => thought_sig
            }]
          }
        }]
      }
      turn2_body = {
        'candidates' => [{
          'content' => { 'role' => 'model', 'parts' => [{ 'text' => 'Flight booked successfully!' }] }
        }]
      }

      # Use chained to_return so turn1 and turn2 use different responses in order
      stub_request(:post, gemini_url)
        .to_return(
          { status: 200, body: turn1_body.to_json, headers: { 'Content-Type' => 'application/json' } },
          { status: 200, body: turn2_body.to_json, headers: { 'Content-Type' => 'application/json' } }
        )

      result    = described_class.call(agent, base_prompt)
      tool_call = result.tool_calls.first

      model_msg  = described_class.format_tool_call_message('gemini', tool_call, raw_parts: result.raw_parts)
      result_msg = described_class.format_tool_result_message('gemini', tool_call.id, tool_call.name, 'Flight booked')

      # thoughtSignature survives into the model message
      expect(model_msg[:parts].first['thoughtSignature']).to eq(thought_sig)
      # id is preserved in both messages
      expect(model_msg[:parts].first['functionCall']['id']).to eq('g3-turn1-id')
      expect(result_msg[:parts].first[:functionResponse][:id]).to eq('g3-turn1-id')

      messages_turn2 = [
        { role: 'user', content: 'Book me a flight GRU to LIS' },
        model_msg,
        result_msg
      ]

      turn2_result = described_class.call(agent, { system: 'You are helpful.', messages: messages_turn2 })

      expect(turn2_result.text?).to be true
      expect(turn2_result.text).to eq('Flight booked successfully!')

      # Verify turn 2 request body included the thoughtSignature from turn 1
      expect(
        a_request(:post, gemini_url).with do |req|
          body       = JSON.parse(req.body)
          model_turn = body['contents']&.find { |c| c['role'] == 'model' }
          model_turn&.dig('parts', 0, 'thoughtSignature') == thought_sig
        end
      ).to have_been_made.once
    end
  end

  # ─── Multi-turn: wire format messages pass through call_gemini unchanged ──

  describe 'call_gemini — wire-format messages pass through without flattening' do
    it 'does not convert Gemini-format messages to text parts' do
      wire_msg = { role: 'model', parts: [{ 'functionCall' => { 'name' => 'foo', 'args' => {} }, 'thoughtSignature' => 'SIG' }] }
      messages  = [{ role: 'user', content: 'Hello' }, wire_msg]

      stub_request(:post, gemini_url)
        .to_return(status: 200,
                   body: { 'candidates' => [{ 'content' => { 'role' => 'model', 'parts' => [{ 'text' => 'Done' }] } }] }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      described_class.call(agent, { system: 'sys', messages: messages })

      expect(WebMock).to have_requested(:post, gemini_url).with do |req|
        body  = JSON.parse(req.body)
        model = body['contents'].find { |c| c['role'] == 'model' }
        model&.dig('parts', 0, 'thoughtSignature') == 'SIG'
      end
    end
  end
end

require 'rails_helper'

RSpec.describe AiAgent::LlmRouterService do
  let(:account)  { create(:account) }
  let(:agent)    { create(:ai_agent, account: account, llm_provider: 'gemini', llm_model: 'gemini-3.1-flash-lite') }
  let(:prompt)   { { system: 'Você é útil.', messages: [{ role: 'user', content: 'oi' }] } }

  let(:success_response) do
    AiAgent::LlmService::LlmResponse.new(type: :text, text: 'Olá!', tool_calls: [], raw_parts: nil)
  end
  let(:transient_error) { StandardError.new('Gemini error: {"error"=>{"code"=>503, "status"=>"UNAVAILABLE"}}') }
  let(:permanent_error) { StandardError.new('Gemini error: {"error"=>{"code"=>400, "status"=>"INVALID_ARGUMENT"}}') }

  around do |example|
    # config.cache_store = :null_store em test — Rails.cache.increment nunca
    # acumula de verdade nesse store (produção usa Redis). Mesmo ajuste do
    # invalid_grant_monitor_spec.rb, aqui pro contador fallback_used_today.
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    example.run
    Rails.cache = original_cache
  end

  before do
    allow_any_instance_of(described_class).to receive(:sleep_before_retry) # sem esperar de verdade nos specs
    # Account/agent factories chamam InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
    # internamente (Featurable) — precisa de um default antes do .with específico, senão
    # QUALQUER outra chamada a find_by explode com MockExpectationError.
    allow(InstallationConfig).to receive(:find_by).and_call_original
    allow(InstallationConfig).to receive(:find_by)
      .with(name: 'CAPTAIN_OPEN_AI_API_KEY')
      .and_return(instance_double(InstallationConfig, value: 'fallback-openai-key'))
  end

  describe 'caminho feliz (sem erro)' do
    it 'não faz retry nem fallback quando o provider original responde de primeira' do
      expect(AiAgent::LlmService).to receive(:call).once.and_return(success_response)
      result = described_class.call(agent, prompt)
      expect(result).to eq(success_response)
    end
  end

  describe 'erro transitório (bug C)' do
    it 'tenta de novo até 3x no total no provider original antes de cair pro fallback' do
      calls = []
      allow(AiAgent::LlmService).to receive(:call) do |called_agent, *|
        calls << called_agent.llm_provider
        called_agent.llm_provider == 'gemini' ? raise(transient_error) : success_response
      end

      result = described_class.call(agent, prompt)
      expect(result).to eq(success_response)
      expect(calls).to eq(%w[gemini gemini gemini openai])
    end

    it 'usa o resultado da 2ª tentativa se ela vier bem, sem precisar do fallback' do
      call_count = 0
      allow(AiAgent::LlmService).to receive(:call) do
        call_count += 1
        call_count == 1 ? raise(transient_error) : success_response
      end

      result = described_class.call(agent, prompt)
      expect(result).to eq(success_response)
      expect(call_count).to eq(2)
    end

    it 'depois de 3 falhas transitórias, cai pro fallback OpenAI (agente=gemini)' do
      allow(AiAgent::LlmService).to receive(:call).and_raise(transient_error)
      allow(AiAgent::LlmService).to receive(:call)
        .with(having_attributes(llm_provider: 'openai', llm_model: 'gpt-4.1-mini'), prompt, tools: [])
        .and_return(success_response)

      result = described_class.call(agent, prompt)
      expect(result).to eq(success_response)
    end

    it 'o agente de fallback usa a chave do CAPTAIN_OPEN_AI_API_KEY, não a do agente original' do
      allow(AiAgent::LlmService).to receive(:call).and_raise(transient_error)
      fallback_agent_seen = nil
      allow(AiAgent::LlmService).to receive(:call) do |called_agent, *|
        if called_agent.llm_provider == 'openai'
          fallback_agent_seen = called_agent
          success_response
        else
          raise transient_error
        end
      end

      described_class.call(agent, prompt)
      expect(fallback_agent_seen.effective_api_key).to eq('fallback-openai-key')
    end

    it 'incrementa o contador fallback_used_today quando o fallback é usado' do
      allow(AiAgent::LlmService).to receive(:call).and_raise(transient_error)
      allow(AiAgent::LlmService).to receive(:call)
        .with(having_attributes(llm_provider: 'openai'), prompt, tools: [])
        .and_return(success_response)

      expect { described_class.call(agent, prompt) }
        .to change(described_class, :fallback_used_today).from(0).to(1)
    end

    it 'se o OpenAI também falhar, sobe o erro original do Gemini' do
      allow(AiAgent::LlmService).to receive(:call).and_raise(transient_error)

      expect { described_class.call(agent, prompt) }.to raise_error(StandardError, transient_error.message)
    end
  end

  describe 'erro não-transitório' do
    it 'pula direto pro fallback sem gastar os 2 retries' do
      allow(AiAgent::LlmService).to receive(:call).and_raise(permanent_error)
      allow(AiAgent::LlmService).to receive(:call)
        .with(having_attributes(llm_provider: 'openai'), prompt, tools: [])
        .and_return(success_response)

      described_class.call(agent, prompt)
      expect(AiAgent::LlmService).to have_received(:call).twice # 1 gemini + 1 openai, sem os 2 retries
    end
  end

  describe 'agente que já não é Gemini' do
    let(:agent) { create(:ai_agent, account: account, llm_provider: 'openai', llm_model: 'gpt-4o') }

    it 'não tenta fallback (não faz sentido OpenAI→OpenAI) — sobe o erro original' do
      allow(AiAgent::LlmService).to receive(:call).and_raise(transient_error)
      expect { described_class.call(agent, prompt) }.to raise_error(StandardError, transient_error.message)
    end
  end

  describe 'histórico já com turnos formatados especificamente pra Gemini' do
    let(:prompt_with_gemini_turn) do
      { system: 'oi', messages: [{ role: 'model', parts: [{ functionCall: { name: 'x', args: {} } }] }] }
    end

    it 'não arrisca traduzir pro formato OpenAI — sobe o erro original em vez de mandar payload malformado' do
      allow(AiAgent::LlmService).to receive(:call).and_raise(transient_error)
      expect { described_class.call(agent, prompt_with_gemini_turn) }.to raise_error(StandardError, transient_error.message)
      expect(AiAgent::LlmService).to have_received(:call).exactly(3).times # só os retries no gemini, nunca o openai
    end
  end
end

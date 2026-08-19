require 'rails_helper'

# Teste crítico de privacidade: garante que o texto que volta pro LLM
# (formatted_for_llm) NUNCA contém telefone do lead, event_id, eventos de
# terceiros nem extendedProperties — mesmo que o endpoint devolva esses dados
# pra auditoria (output_result). E que SEMPRE há texto legível, inclusive em erro.
RSpec.describe 'Native calendar tools — privacidade do formatted_for_llm' do
  let(:account)  { create(:account) }
  let(:ai_agent) { create(:ai_agent, account: account) }
  let(:context)  { { conversation_id: 'conv-1', contact_id: '99', account_id: account.id } }

  before { AiAgent::NativeToolRegistry.activate(ai_agent, 'google_calendar') }

  def tool(native_key)
    ai_agent.tools.find_by(native_key: native_key)
  end

  def run(native_key, args = {})
    AiAgent::ToolExecutor.new(tool(native_key), args, context).call
  end

  PII_PATTERNS = ['+5519999990000', 'evt_secret', 'extendedProperties', 'lead_phone'].freeze

  it 'criar_agendamento: mensagem + meet_link ao LLM, sem PII; auditoria guarda o telefone' do
    stub_request(:post, %r{/ai_agent_calendar/criar_agendamento}).to_return(
      status: 200,
      body: { status: 'created', event_id: 'evt_secret', html_link: 'https://cal/evt_secret',
              meet_link: 'https://meet.google.com/abc-defg-hij',
              meet_link_text: ' Link da reunião: https://meet.google.com/abc-defg-hij',
              start: '2026-06-23T14:00:00-03:00', mensagem: 'Reunião agendada com sucesso para 23/06 às 14:00.',
              _audit: { lead_phone: '+5519999990000', conversation_id: 'conv-1', contact_id: '99' } }.to_json,
      headers: { 'Content-Type' => 'application/json' }
    )

    result = run('gcal_criar_agendamento', 'data_hora_inicio' => '2026-06-23T14:00:00-03:00')

    PII_PATTERNS.each { |p| expect(result.formatted_for_llm).not_to include(p) }
    expect(result.formatted_for_llm).to include('agendada')
    # meet_link do próprio evento PODE aparecer (não vaza nada de terceiros)
    expect(result.formatted_for_llm).to include('https://meet.google.com/abc-defg-hij')
    # mas event_id continua fora do texto pro LLM
    expect(result.formatted_for_llm).not_to include('evt_secret')
    # auditoria (output_result) preserva o telefone derivado server-side
    expect(AiAgent::ToolExecution.last.output_result.dig('_audit', 'lead_phone')).to eq('+5519999990000')
  end

  it 'criar_agendamento: sem meet_link, formatted_for_llm OMITE a linha de reunião' do
    stub_request(:post, %r{/ai_agent_calendar/criar_agendamento}).to_return(
      status: 200,
      body: { status: 'created', event_id: 'evt_x', html_link: 'https://cal/evt_x',
              meet_link: nil, meet_link_text: '',
              mensagem: 'Reunião agendada com sucesso para 23/06 às 14:00.',
              _audit: { lead_phone: '+5519999990000', conversation_id: 'conv-1', contact_id: '99' } }.to_json,
      headers: { 'Content-Type' => 'application/json' }
    )

    result = run('gcal_criar_agendamento', 'data_hora_inicio' => '2026-06-23T14:00:00-03:00')

    expect(result.formatted_for_llm).to include('agendada')
    expect(result.formatted_for_llm).not_to include('Link da reunião')
  end

  it 'cancelar_agendamento: mensagem ao LLM sem PII' do
    stub_request(:post, %r{/ai_agent_calendar/cancelar_agendamento}).to_return(
      status: 200,
      body: { cancelled_count: 1, status: 'cancelled', mensagem: '1 agendamento(s) cancelado(s) com sucesso.',
              _audit: { lead_phone: '+5519999990000', conversation_id: 'conv-1', contact_id: '99' } }.to_json,
      headers: { 'Content-Type' => 'application/json' }
    )

    result = run('gcal_cancelar_agendamento')

    PII_PATTERNS.each { |p| expect(result.formatted_for_llm).not_to include(p) }
    expect(result.formatted_for_llm).to include('cancelado')
  end

  it 'consultar_horarios_livres: só slots livres, sem dados de eventos' do
    stub_request(:post, %r{/ai_agent_calendar/consultar_horarios_livres}).to_return(
      status: 200,
      body: { slots: [{ inicio_iso: '2026-06-23T09:00:00-03:00', fim_iso: '2026-06-23T10:00:00-03:00', duracao_min: 60 }],
              total: 1 }.to_json,
      headers: { 'Content-Type' => 'application/json' }
    )

    result = run('gcal_consultar_horarios_livres',
                 'data_inicio' => '2026-06-23T09:00:00-03:00', 'data_fim' => '2026-06-23T18:00:00-03:00')

    %w[extendedProperties lead_phone evt_ summary attendees].each do |p|
      expect(result.formatted_for_llm).not_to include(p)
    end
    expect(result.formatted_for_llm).to include('inicio_iso')
  end

  it 'sempre retorna texto legível mesmo com a tool/Google fora do ar' do
    stub_request(:post, %r{/ai_agent_calendar/criar_agendamento}).to_return(status: 502, body: 'gateway down')

    result = run('gcal_criar_agendamento', 'data_hora_inicio' => '2026-06-23T14:00:00-03:00')

    expect(result.formatted_for_llm).to be_present
    expect(result.formatted_for_llm).to match(/erro|servi/i)
    PII_PATTERNS.each { |p| expect(result.formatted_for_llm).not_to include(p) }
  end
end

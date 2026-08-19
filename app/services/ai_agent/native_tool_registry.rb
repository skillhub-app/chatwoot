# Cadastra/remove tools NATIVAS num ai_agent. Tools nativas são linhas
# AiAgent::Tool (is_native: true) que apontam pra endpoints internos do Chatwoot
# e se autenticam via X-Internal-Token (${INTERNAL_API_TOKEN}, resolvido em
# runtime pelo ToolExecutor). A UI mostra badge "Nativa" e bloqueia editar
# URL/schema; só o toggle active fica editável.
#
# Privacidade: os schemas NÃO expõem lead_phone nem event_id — esses dados são
# derivados server-side do _context nos endpoints.
class AiAgent::NativeToolRegistry
  CATALOG = {
    'google_calendar' => [
      {
        native_key:  'gcal_consultar_horarios_livres',
        name:        'consultar_horarios_livres',
        path:        'consultar_horarios_livres',
        description: 'Consulta horários livres na agenda para marcar uma reunião com o lead.',
        when_to_use: 'Use quando o lead quiser saber horários disponíveis ou marcar uma reunião/consulta.',
        parameters_schema: {
          'type' => 'object',
          'properties' => {
            'data_inicio'     => { 'type' => 'string', 'description' => 'Início da janela de busca em ISO 8601 (ex: 2026-06-23T09:00:00).' },
            'data_fim'        => { 'type' => 'string', 'description' => 'Fim da janela de busca em ISO 8601 (ex: 2026-06-27T18:00:00).' },
            'duracao_minutos' => { 'type' => 'integer', 'description' => 'Duração desejada em minutos (opcional; usa o padrão da agenda se omitido).' }
          },
          'required' => %w[data_inicio data_fim]
        },
        # Sem response_template: o LLM recebe os slots livres (JSON, sem PII).
        response_template: nil
      },
      {
        native_key:  'gcal_criar_agendamento',
        name:        'criar_agendamento',
        path:        'criar_agendamento',
        description: 'Cria um agendamento/reunião na agenda para o lead atual.',
        when_to_use: 'Use quando o lead confirmar um horário específico para a reunião.',
        parameters_schema: {
          'type' => 'object',
          'properties' => {
            'data_hora_inicio' => { 'type' => 'string', 'description' => 'Data e hora de início em ISO 8601 (ex: 2026-06-23T14:00:00).' },
            'titulo'           => { 'type' => 'string', 'description' => 'Título da reunião (opcional).' },
            'descricao'        => { 'type' => 'string', 'description' => 'Descrição/observações (opcional).' }
          },
          'required' => %w[data_hora_inicio]
        },
        # 'mensagem' (sem PII) + 'meet_link_text' (link Meet do próprio evento, ou
        # vazio). event_id/_audit ficam só no log. meet_link_text já vem pronto do
        # EventCreatorService (engine de template não tem condicional).
        response_template: '{{mensagem}}{{meet_link_text}}'
      },
      {
        native_key:  'gcal_cancelar_agendamento',
        name:        'cancelar_agendamento',
        path:        'cancelar_agendamento',
        description: 'Cancela o(s) agendamento(s) do lead atual.',
        when_to_use: 'Use quando o lead pedir para cancelar ou desmarcar a reunião dele.',
        parameters_schema: {
          'type' => 'object',
          'properties' => {},
          'required' => []
        },
        response_template: '{{mensagem}}'
      }
    ]
  }.freeze

  def self.activate(ai_agent, provider_key)
    new(ai_agent).activate(provider_key)
  end

  def self.deactivate(ai_agent, provider_key)
    new(ai_agent).deactivate(provider_key)
  end

  def self.find_native_tools(ai_agent, provider_key = nil)
    keys = native_keys_for(provider_key)
    ai_agent.tools.native.where(native_key: keys)
  end

  def self.native_keys_for(provider_key)
    defs = provider_key ? CATALOG.fetch(provider_key, []) : CATALOG.values.flatten
    defs.map { |d| d[:native_key] }
  end

  def initialize(ai_agent)
    @ai_agent = ai_agent
  end

  # Idempotente: cria ou atualiza as 3 tools nativas e as deixa ativas.
  def activate(provider_key)
    CATALOG.fetch(provider_key).map { |definition| upsert(definition) }
  end

  def deactivate(provider_key)
    self.class.find_native_tools(@ai_agent, provider_key).update_all(active: false)
  end

  private

  def upsert(definition)
    tool = @ai_agent.tools.find_or_initialize_by(native_key: definition[:native_key])
    tool.assign_attributes(
      name:              definition[:name],
      description:       definition[:description],
      when_to_use:       definition[:when_to_use],
      parameters_schema: definition[:parameters_schema],
      response_template: definition[:response_template],
      http_method:       'POST',
      endpoint_url:      endpoint_url_for(definition[:path]),
      headers:           { 'X-Internal-Token' => '${INTERNAL_API_TOKEN}' },
      timeout_seconds:   20,
      is_native:         true,
      active:            true
    )
    tool.save!
    tool
  end

  def endpoint_url_for(path)
    base = ENV.fetch('FRONTEND_URL', 'http://localhost:3000')
    "#{base}/api/v1/accounts/#{@ai_agent.account_id}/ai_agent_calendar/#{path}?ai_agent_id=#{@ai_agent.id}"
  end
end

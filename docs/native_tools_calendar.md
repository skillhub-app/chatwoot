# Tools nativas de Google Calendar (v1.0.0.62)

Tools "nativas" são `AiAgent::Tool` (`is_native: true`) cadastradas
automaticamente pelo sistema, apontando para endpoints internos do Chatwoot.
O LLM as enxerga como qualquer outra function tool, mas a URL e o schema são
imutáveis pela UI (só dá pra ativar/desativar).

## As 3 tools (provider `google_calendar`)

| native_key | name (LLM) | O que faz |
|---|---|---|
| `gcal_consultar_horarios_livres` | `consultar_horarios_livres` | Retorna **apenas** slots LIVRES (via Freebusy). Nunca lista eventos. |
| `gcal_criar_agendamento` | `criar_agendamento` | Cria evento `private` com `extendedProperties.private.{lead_phone,conversation_id,created_by}`. |
| `gcal_cancelar_agendamento` | `cancelar_agendamento` | Cancela o(s) evento(s) do lead atual (busca por `lead_phone`). |

### Schemas expostos ao LLM
- `consultar_horarios_livres`: `data_inicio` (ISO, obrigatório), `data_fim` (ISO, obrigatório), `duracao_minutos` (int, opcional).
- `criar_agendamento`: `data_hora_inicio` (ISO, obrigatório), `titulo` (opcional), `descricao` (opcional).
- `cancelar_agendamento`: sem parâmetros.

> Os schemas **não** têm `lead_phone` nem `event_id`. Esses dados são derivados
> server-side a partir do `_context` da conversa.

## Fluxo de execução

```
LLM → ToolExecutor (HTTP) → POST FRONTEND_URL/api/v1/accounts/:id/ai_agent_calendar/<acao>?ai_agent_id=<id>
                            header X-Internal-Token: ${INTERNAL_API_TOKEN}
                            body: { ...args do LLM, _context: { conversation_id, contact_id, account_id } }
```

- O `ToolExecutor` injeta `_context` no corpo e resolve `${INTERNAL_API_TOKEN}`
  da ENV em runtime (o valor real nunca fica no banco).
- O controller `Api::V1::Accounts::AiAgentCalendarController` valida o token
  interno, o multi-tenant (`ai_agent.account_id == account_id` → 403) e exige
  `_context` (→ 400).

## Privacidade (regras de ouro)

1. **`lead_phone` SEMPRE do `_context`** (`contact_id` → `Contact#phone_number`),
   **nunca** do input do LLM (anti-spoofing).
2. **`consultar_horarios_livres` nunca retorna eventos** — só Freebusy (períodos
   ocupados) e devolve apenas slots livres.
3. **`criar_agendamento`** força `visibility: 'private'` e grava
   `extendedProperties.private.lead_phone` (chave usada no cancelamento).
4. **`cancelar_agendamento`** só cancela eventos cujo
   `extendedProperties.private.lead_phone` bate (re-checado em código, além do
   filtro server-side `privateExtendedProperty`). Nunca aceita `event_id`.
5. **O texto que volta pro LLM (`formatted_for_llm`)** é só `mensagem`
   (criar/cancelar) ou a lista de slots (consultar) — **sem** telefone,
   `event_id` ou `extendedProperties`. O telefone vai só no `_audit`
   (→ `ai_agent_tool_executions.output_result`).

## Auditoria
Cada execução gera um `AiAgent::ToolExecution` (automático pelo `ToolExecutor`):
- `input_params`: argumentos do LLM.
- `output_result`: resposta do endpoint, incluindo `_audit` com `lead_phone`,
  `conversation_id` e `contact_id`.

## Operação

- **ENV obrigatória**: `INTERNAL_API_TOKEN` (string aleatória longa) nos
  containers `chatwoot_rails` e `chatwoot_sidekiq`. Sem ela, as tools nativas
  retornam 401.
- **Cadastro automático**: ao conectar o Google Calendar (callback OAuth, após a
  primary calendar ser setada), `AiAgent::NativeToolRegistry.activate` cadastra
  as 3 tools.
- **Backfill**: `bundle exec rake google_calendar:backfill_primary` faz o
  backfill da primary e ativa as tools nativas em todos os schedules conectados.
  Há também `rake google_calendar:activate_native_tools` (só ativação).

## Como criar tools nativas para OUTRO provider no futuro

1. Adicione uma entrada em `AiAgent::NativeToolRegistry::CATALOG` com a chave do
   provider e a lista de tools (`native_key`, `name`, `path`, `description`,
   `when_to_use`, `parameters_schema`, `response_template`).
2. Crie os endpoints internos correspondentes (mesma proteção:
   `authenticate_internal_request!` + multi-tenant + `_context`).
3. Chame `AiAgent::NativeToolRegistry.activate(ai_agent, '<provider>')` no ponto
   de conexão do provider.
4. Lembre do `response_template` para **não vazar PII** pro LLM (exponha só uma
   `mensagem` legível; dados sensíveis ficam no `_audit`/`output_result`).

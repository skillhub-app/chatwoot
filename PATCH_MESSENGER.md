# PATCH FORK-SPECIFIC — Facebook Messenger `messaging_type`

> ⚠️ Este patch é **específico do fork** e **NÃO existe no Chatwoot upstream**.
> Ele PRECISA sobreviver a merges/updates do Chatwoot. Se um update sobrescrever
> `app/services/facebook/send_on_facebook_service.rb`, **reaplique este patch**.

## Contexto / bug corrigido

O Chatwoot upstream envia toda resposta do Messenger com:

```ruby
messaging_type: 'MESSAGE_TAG',
tag: 'ACCOUNT_UPDATE'   # (ou HUMAN_AGENT se ENABLE_MESSENGER_CHANNEL_HUMAN_AGENT)
```

A Meta **descontinuou a tag `ACCOUNT_UPDATE`**. Qualquer envio com ela retorna:

```
HTTP 400
code: 100, error_subcode: 1893061
error_user_title: "A tag de mensagem descontinuada não é permitida"
error_user_msg:   "Você está tentando enviar uma mensagem com tag, mas esse
                   recurso não é permitido. Para enviar uma mensagem de
                   utilidade, use um modelo de utilidade aprovado."
```

Resultado: **toda resposta da IA no Messenger falhava** com "Invalid parameter"
(inbox 18 "Facebook | Volponi", conta 1). Diagnóstico confirmado em 2026-07-24
capturando a resposta crua da Graph API.

## Regra adotada (decisão do produto)

- **Dentro da janela de 24h** (última mensagem recebida do lead há < 24h):
  enviar com `messaging_type: 'RESPONSE'` e **sem tag**. ✅ testado: HTTP 200 +
  `message_id` (inclusive pelo caminho real do gem `facebook-messenger`).
- **Fora da janela de 24h**: **NÃO enviar**. Descartar silenciosamente (log
  `[Facebook][messenger][out_of_24h_window]`), **sem** tag descontinuada e
  **sem** marcar a mensagem como `failed`.
- **Não** usar `HUMAN_AGENT` nem depender de permissão nova da Meta.

## O que o patch faz (`app/services/facebook/send_on_facebook_service.rb`)

1. `perform_reply`: `return unless within_messaging_window?` (gate de 24h).
2. `fb_text_message_params` e `fb_attachment_message_params`:
   `messaging_type: 'RESPONSE'`, **removido** `tag:`.
3. Removido o método `message_tag` (era a fonte da tag `ACCOUNT_UPDATE`).
4. Adicionado `within_messaging_window?` — check **por tempo** (última incoming
   >= 24h atrás). NÃO usar `sent_first_outgoing_message_after_24_hours?` para
   isso: aquele método conta mensagens (`count == 1`) e bloquearia o 2º+ chunk
   da resposta da IA (que é enviada em pedaços).

## Notas relacionadas

- O gem `facebook-messenger 2.0.1` tem a versão da Graph **`v3.2` hardcoded**,
  mas testamos que ela **aceita `RESPONSE`** (HTTP 200 + message_id), então
  **não** foi necessário forçar v21.0 no envio. Se um dia a Meta cortar v3.2,
  o envio vai quebrar e aí sim será preciso forçar uma versão atual.
- `InstallationConfig['FACEBOOK_API_VERSION']` foi setado para `v21.0`
  (era `v18.0`, depreciada). Esse config NÃO afeta o envio pelo gem (v3.2), só
  outras chamadas Graph do Chatwoot.
- Verify token do webhook (`/bot`): `FB_VERIFY_TOKEN` no InstallationConfig.

## Como reaplicar após um update do Chatwoot

Ver o commit da branch `fix/messenger-response-messaging-type` (base v1.0.0.70)
ou reaplicar os 4 pontos acima manualmente no
`app/services/facebook/send_on_facebook_service.rb`.

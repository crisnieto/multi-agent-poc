# Contrato interno: API de chat ↔ actor Codex

Este contrato viaja por `atenet-router`; el cliente es la API de chat con identidad SPIFFE autorizada y cabecera `ate-target-actor: <atespace>/<actor_id>`. Nunca se expone el actor directamente al navegador.

## `POST /turns`

Solicitud JSON: `{"request_id":"uuid","text":"mensaje"}`. `request_id` es único por sesión y permite deduplicar reintentos. El actor acepta un turno a la vez; ante otro turno concurrente responde `409 actor_busy`.

Respuesta `Content-Type: text/event-stream` con eventos ordenados:

```text
event: started
data: {"request_id":"...","thread_id":"..."}

event: delta
data: {"request_id":"...","text":"fragmento"}

event: completed
data: {"request_id":"...","text":"respuesta final"}
```

En falla emite `event: failed` con `code` y `message` no sensibles. `completed` y `failed` son mutuamente excluyentes. El adaptador comprueba el estado final del turno Codex antes de enviar `completed`.

## `GET /healthz`

`200` si el adaptador y app-server local responden. `503` si no está listo. No incluye credenciales ni configuración MCP.

## Persistencia y egreso

El adaptador conserva el identificador de hilo y datos necesarios para `thread/resume` dentro del filesystem del actor que entra en el snapshot. En kind y EKS, el gateway de egreso de Substrate permite únicamente destinos OpenAI y MCP aprobados e inyecta credenciales fuera del actor. El arranque standalone local puede recibir una clave solo como variable de proceso para su smoke test; esa clave no entra en archivos, imágenes, logs, commits ni pushes. Si la integración con Substrate muestra que Codex requiere una clave real dentro del sandbox, el gate falla y se documenta antes de continuar.

## Validaciones de integración

1. El router deja pasar la transmisión incremental sin buffer completo.
2. El mismo hilo conserva contexto después de suspender y reanudar en otro worker.
3. Una falla de red o del modelo produce `failed`, nunca `completed`.
4. Un reintento con el mismo `request_id` no ejecuta dos turnos.

# Modelo de datos

Los registros de la API propia son efímeros durante una ventana de prueba. Substrate es la fuente de verdad para estado de actores y workers; la API guarda correlación e historial observable.

## Session

| Campo | Tipo | Regla |
| --- | --- | --- |
| id | UUID | Inmutable, único |
| actor_id | string | Único, relación 1:1 con un Actor de Substrate |
| title | string | Opcional, máximo 120 caracteres |
| status | enum | `creating`, `ready`, `busy`, `suspended`, `failed`, `closed` |
| created_at, updated_at, closed_at | timestamp UTC | `closed_at` solo al cerrar |
| last_request_id | UUID | Opcional |

El historial visible se reconstruye de solicitudes y eventos; el contexto efectivo del agente vive en el estado del actor y su snapshot.

## ChatRequest

| Campo | Tipo | Regla |
| --- | --- | --- |
| id | UUID | Único; clave de idempotencia opcional por sesión |
| session_id | UUID | FK a Session |
| user_text | string | 1 a 16 000 caracteres |
| status | enum | `queued`, `running`, `completed`, `failed`, `timed_out`, `cancelled` |
| created_at, started_at, finished_at | timestamp UTC | Orden temporal coherente |
| final_text | string | Solo después de finalización |
| error_code | string | Solo en falla/timeout |

Máximo un turno `queued` o `running` por sesión. Un turno en otra sesión puede ejecutarse en paralelo si hay capacidad.

## Event

| Campo | Tipo | Regla |
| --- | --- | --- |
| id | entero monotónico | Cursor para SSE y replay |
| at | timestamp UTC | Hora de observación |
| type | enum | `session.created`, `actor.assigned`, `actor.resuming`, `actor.running`, `actor.suspending`, `actor.suspended`, `worker.idle`, `worker.busy`, `request.queued`, `request.started`, `message.delta`, `request.completed`, `request.failed`, `capacity.waiting` |
| session_id, actor_id, worker_id, request_id | string/UUID | Opcionales según evento; `session_id` requerido para eventos de chat |
| source | enum | `substrate`, `agent`, `control_plane` |
| payload | JSON | Campos tipados por evento, sin credenciales ni prompts en telemetría de topología |

El historial diferencia estados confirmados por Substrate de eventos locales de la API. Una asignación solo se anuncia como confirmada al observar el worker en Substrate.

## ActorView y WorkerView

`ActorView` contiene `actor_id`, `session_id`, `state` (`suspended`, `resuming`, `running`, `suspending`, `crashed`, `unknown`), `worker_id` opcional, `template_version` y `observed_at`. `WorkerView` contiene `worker_id`, `pod_name`, `state` (`idle`, `busy`, `unavailable`), `actor_id` opcional y `observed_at`. Ambos se derivan de la API de Substrate, con cache máxima de 5 segundos para UI; no reemplazan su fuente de verdad.

## TrialWindow

| Campo | Tipo | Regla |
| --- | --- | --- |
| id | UUID | Una por despliegue |
| aws_region, cluster_name | string | Configuración de la ventana |
| started_at, planned_stop_at, stopped_at | timestamp UTC | `planned_stop_at` obligatorio |
| budget_usd | decimal | Máximo 80 menos gasto previo del mes |
| estimated_usd, observed_usd | decimal | Estimación previa y costo observado, con hora de lectura |
| status | enum | `planned`, `running`, `stopping`, `stopped`, `cleanup_failed` |

## Transiciones y borrado

- `Session`: `creating → ready → busy → ready/suspended`; `suspended → busy` al reanudar; cualquier estado activo puede pasar a `failed` y luego a `closed` tras limpieza.
- `ChatRequest`: `queued → running → completed/failed/timed_out/cancelled`. Un evento terminal se emite una sola vez.
- `ActorView`: refleja el ciclo de Substrate `suspended → resuming → running → suspending → suspended`; `unknown` indica falta de observación, no estado confirmado.
- Al cerrar una sesión se elimina su actor y se retienen registros locales hasta terminar la ventana. Al destruir la ventana se borran SQLite, PostgreSQL y snapshots S3; no se promete recuperación de chats entre ventanas.

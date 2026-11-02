# Tasks: PoC de Agent Substrate en EKS

**Input**: `specs/001-substrate-agents-poc/{spec,plan,research,data-model,quickstart}.md` y `contracts/`  
**Regla de ejecución**: los cuatro componentes deben arrancar y pasar sus smoke tests locales individuales; luego debe pasar la integración local con Substrate real. Ningún `terraform apply` de AWS se ejecuta antes de ese gate, del preflight financiero y de disponer de destrucción/auditoría.
**Tests**: se incluyen pruebas de contrato e integración que comprueban comportamiento observable, compatibilidad y presupuesto.

## Phase 1: Setup

**Goal**: monorepo compilable y configuración local reproducible.

- [X] T001 Crear `package.json`, `pnpm-workspace.yaml` y `tsconfig.base.json` con workspaces para frontend, API y actor, Node.js 22 y comandos build/lint/typecheck.
- [X] T002 [P] Crear `apps/web/package.json` y `apps/web/vite.config.ts` con React, TypeScript y proxy local `/api`.
- [X] T003 [P] Crear `apps/control-plane/package.json` y `apps/control-plane/tsconfig.json` con Fastify y SQLite.
- [X] T004 [P] Crear `apps/codex-actor/package.json` y `apps/codex-actor/tsconfig.json` con adaptador HTTP y ejecución local de Codex app-server.
- [X] T005 Crear `infra/config/example.env`, revisar `.gitignore` y `scripts/check-secrets.sh`, y verificar que `.githooks/pre-commit`/`.githooks/pre-push` están activos y bloquean claves OpenAI en commits y pushes.
- [X] T006 Crear `infra/substrate.lock` e `infra/README.md` con tag/commit SHA inmutable de Substrate y pasos para obtener exactamente esa versión.

**Checkpoint**: los tres workspaces propios compilan sin AWS.

---

## Phase 2: Foundational — cuatro arranques locales independientes

**Goal**: verificar la expresión mínima de frontend, API, actor Codex y gestión Substrate, cada uno sin depender de los otros componentes propios y sin recursos AWS.

- [X] T007 [P] Crear `infra/local/up.sh` e `infra/local/down.sh` para crear/eliminar kind y registro local usando el commit de `infra/substrate.lock`; detectar recursos insuficientes del host y no acceder a AWS.
- [X] T008 Crear `infra/local/install-substrate.sh` para instalar Substrate y almacenamiento local compatible en kind, aplicar un WorkerPool pequeño y esperar readiness de API, router, gateway y workers.
- [X] T009 Crear `infra/local/smoke-substrate.sh` para crear un actor de ejemplo, enviar petición, observar worker, suspender, comprobar snapshot y reanudar; registrar éxito/fallo del componente 4.
- [X] T010 [P] Crear `apps/control-plane/src/server.ts` y `apps/control-plane/src/auth.ts` con `/api/healthz`, login de operador y cookie HttpOnly.
- [X] T011 Crear `apps/control-plane/src/db/schema.sql` y `apps/control-plane/src/db/index.ts` con tablas/índices de sesiones, solicitudes y eventos para SQLite local.
- [X] T012 Crear `apps/control-plane/src/adapters/mock.ts`, `apps/control-plane/src/routes/sessions.ts`, `apps/control-plane/src/routes/requests.ts`, `apps/control-plane/src/events/sse.ts` e `infra/local/smoke-control-plane.sh` con rutas mínimas de sesión/turno y SSE sobre actor simulado, para iniciar y verificar la API sin Substrate/Codex; rotular los datos simulados.
- [X] T013 [P] Crear `apps/codex-actor/Dockerfile` y `apps/codex-actor/config/system-prompt.md` con Codex fijado y prompt mínimo; dejar una sola definición de configuración del actor.
- [X] T014 Crear `apps/codex-actor/src/codex-client.ts` para iniciar app-server por stdio, crear/reanudar hilo, iniciar turno y distinguir deltas, éxito y error terminal.
- [X] T015 Crear `apps/codex-actor/src/server.ts` e `infra/local/smoke-codex-actor.sh` con `/healthz`, `POST /turns`, respuesta incremental, deduplicación y un turno real acotado; pasar clave OpenAI solo por variable de proceso, sin archivo, log ni capa de imagen.
- [X] T016 [P] Crear `apps/web/index.html`, `apps/web/src/main.tsx`, `apps/web/src/pages/LocalDemo.tsx` e `infra/local/smoke-web.sh` para arrancar frontend sin API, abrir chat de ejemplo y visualizar topología simulada rotulada como tal.
- [X] T017 Crear `infra/local/verify-components.sh` e `infra/reports/local-components.md` para ejecutar los cuatro smoke tests T009/T012/T015/T016 por separado, registrar versión, comandos y resultados y fallar si cualquiera no funciona.
- [X] T018 Crear `infra/local/verify-cleanup.sh` para confirmar que T007 elimina kind, registro, almacenamiento y procesos locales de la prueba.

**Checkpoint obligatorio**: cuatro resultados locales individuales aprobados en `infra/reports/local-components.md`. No se crea infraestructura AWS.

---

## Phase 3: User Story 1 — Observar multiplexación local (Priority: P1) 🎯 MVP

**Goal**: integrar los cuatro componentes en local y observar sesiones, actores y workers reales de Substrate.

**Independent Test**: con dos workers kind, crear tres sesiones, completar turnos, suspender y reanudar; verificar que al menos dos actores usan el mismo worker en tiempos distintos y que cada sesión conserva contexto.

- [X] T019 [US1] Crear `infra/local/build-load-actor.sh` e `infra/local/actor-template.yaml` para construir/publicar la imagen del actor en el registro local antes de registrar su plantilla inmutable en Substrate.
- [X] T020 [P] [US1] Implementar `apps/control-plane/src/substrate/client.ts` para crear, consultar, suspender y eliminar actores de Substrate con errores tipados e IDs correlacionables.
- [X] T021 [US1] Implementar `apps/control-plane/src/sessions/service.ts` y conectar `apps/control-plane/src/routes/sessions.ts` de T012 a Substrate real con vínculo 1:1 sesión–actor y rutas `GET/POST /sessions`, `GET/DELETE /sessions/{id}`.
- [X] T022 [US1] Implementar `apps/control-plane/src/requests/model.ts` y `apps/control-plane/src/requests/service.ts` con turno mínimo `queued/running/completed/failed`, un turno por sesión y resultado terminal persistido.
- [X] T023 [US1] Conectar `apps/control-plane/src/routes/requests.ts` y `apps/control-plane/src/events/sse.ts` de T012 al servicio real con `POST /sessions/{id}/requests`, `GET /requests/{id}`, `GET /requests/{id}/events` y deltas SSE; reservar replay avanzado para US2.
- [X] T024 [US1] Implementar `apps/control-plane/src/actor/router-client.ts` con cliente autorizado, `ate-target-actor`, streaming por router y timeout, sin asignar workers desde la aplicación.
- [X] T025 [US1] Implementar `apps/control-plane/src/events/store.ts` para persistir hora, origen y relación sesión–actor–worker sin secretos ni contenido sensible de topología.
- [X] T026 [US1] Implementar `apps/control-plane/src/topology/service.ts` y `apps/control-plane/src/routes/topology.ts` con estados observados de Substrate, `GET /topology` y SSE de cambios; marcar `unknown` si falta observación.
- [X] T027 [US1] Implementar `apps/control-plane/src/sessions/idle-suspender.ts` con plazo configurable y suspensión solo sin turno activo.
- [X] T028 [P] [US1] Crear `apps/web/src/components/TopologyPanel.tsx` y `apps/web/src/components/Timeline.tsx` con workers libres/ocupados/no disponibles y eventos fechados.
- [X] T029 [US1] Crear `apps/web/src/pages/Dashboard.tsx` y `apps/web/src/api/client.ts` para crear sesiones, enviar turno, ver deltas y vincularlo a topología real.
- [X] T030 [US1] Crear `infra/local/egress-policy.yaml`, `infra/local/check-egress.sh` e `infra/local/smoke-integrated.sh` para crear el secreto solo en ejecución, inyectar la clave OpenAI fuera del actor mediante el gateway local, verificar que no aparece en sandbox/logs/manifiesto y después conectar los cuatro componentes y comprobar turno, asignación, suspensión y reanudación sin mocks de Substrate.
- [X] T031 [US1] Crear `tests/e2e/multiplexing.spec.ts` para validar en kind 3 actores/2 workers, reutilización temporal y cinco ciclos suspend/resume con contexto propio.
- [X] T032 [US1] Ejecutar T030/T031, registrar IDs, tiempos y resultados de SC-001/SC-003/SC-007 en `infra/reports/local-integration.md` y marcar gate local fallido si la UI muestra una asignación no confirmada.

**Checkpoint obligatorio antes de AWS**: `local-components.md` y `local-integration.md` aprobados. El MVP funciona localmente sin infraestructura AWS.

---

## Phase 4: User Story 2 — Conversar con el agente (Priority: P2)

**Goal**: mejorar chat local con aislamiento, espera por capacidad, reconexión y errores explícitos.

**Independent Test**: alternar dos sesiones sin cruzar contexto, completar diez conversaciones con resultado o error, cortar SSE y recuperar estado final.

- [X] T033 [P] [US2] Extender `apps/control-plane/src/requests/model.ts` con `timed_out/cancelled`, clave de idempotencia y validación de transiciones.
- [ ] T034 [US2] Extender `apps/control-plane/src/requests/service.ts` con espera de capacidad configurable y terminal único ante timeout/cancelación.
- [ ] T035 [US2] Extender `apps/control-plane/src/events/sse.ts` con `Last-Event-ID`, replay, heartbeats y backpressure; nunca emitir `completed` para respuesta parcial.
- [X] T036 [US2] Verificar en `apps/codex-actor/src/codex-client.ts` que el hilo y archivos del actor sobreviven snapshot/reanudación y que dos actores no comparten estado.
- [ ] T037 [P] [US2] Crear `apps/web/src/components/ChatPanel.tsx` y `apps/web/src/hooks/useRequestEvents.ts` con historial, espera, error y reconexión que consulta `GET /requests/{id}`.
- [ ] T038 [US2] Crear `apps/codex-actor/config/mcp.json` y `apps/codex-actor/README.md` con un MCP mínimo de permisos explícitos y prueba de inicialización; reutilizar el prompt de T013.
- [X] T039 [US2] Crear `tests/contract/chat-api.spec.ts` para validar códigos, estados, SSE y replay del contrato con actor simulado.
- [ ] T040 [US2] Crear `tests/e2e/chat-isolation.spec.ts` y `tests/e2e/chat-reconnect.spec.ts` para validar contexto por actor y recuperación tras cortar SSE.
- [ ] T041 [US2] Registrar en `infra/reports/chat-validation.md` diez conversaciones y una prueba cronometrada de dos minutos para ubicar sesión, actor y worker (SC-002/SC-006).

**Checkpoint**: chat completo e integración local probados; el gate local sigue siendo condición para AWS.

---

## Phase 5: User Story 3 — Desplegar y apagar en AWS (Priority: P3)

**Goal**: reproducir en EKS los componentes ya verificados localmente, con presupuesto y ruta de limpieza listos antes del primer `apply`.

**Independent Test**: con gate local aprobado, desplegar, conversar, observar multiplexación, destruir, auditar y recrear en otra ventana; medir tiempos de SC-004.

- [X] T042 [US3] Crear `infra/scripts/cost-estimate.ts` e `infra/scripts/preflight-budget.sh` que exijan tarifas regionales de EKS/nodos/red/EBS/S3/logs/OpenAI, gasto mensual previo y horas; rechacen precios desconocidos o proyección superior a USD 80 menos reserva del 20%.
- [X] T043 [P] [US3] Crear `infra/terraform/budget.tf` con alertas configurables a USD 40/70 y `infra/scripts/stop-timer.sh` con hora de apagado de la ventana; documentar retraso de AWS Budgets.
- [X] T044 [US3] Crear `infra/scripts/destroy.sh`, `infra/scripts/audit-residuals.sh` e `infra/scripts/verify-cleanup.sh` para destruir clúster/volúmenes/bucket de la PoC y fallar ante recursos facturables inesperados; probarlos contra estado Terraform local antes del primer `apply` AWS.
- [X] T045 [US3] Crear `infra/terraform/versions.tf`, `variables.tf` y `outputs.tf` con región, EKS 1.37, duración, tamaño de nodos/pool y etiquetas de costo.
- [X] T046 [US3] Crear `infra/terraform/network.tf` y `eks.tf` con VPC, EKS, managed node group EC2, endpoint restringido y sin NAT/LoadBalancer público.
- [X] T047 [P] [US3] Crear `infra/terraform/storage-iam.tf` con S3 privado y roles mínimos para sidecars de `atelet` y `ate-api-server`.
- [ ] T048 [US3] Crear `infra/k8s/substrate/` con overlay S3 para ambos sidecars, gVisor, ingreso autorizado y WorkerPool configurable.
- [ ] T049 [US3] Crear `infra/scripts/preflight-eks.sh`, `infra/k8s/smoke/pod-certificate.yaml` y `infra/scripts/check-pod-certificates.sh` para validar versión/quotas antes del `apply` y API discovery/montaje de certificados tras crear EKS.
- [ ] T050 [US3] Crear `infra/scripts/install-substrate.sh` y `infra/scripts/smoke-substrate.sh` para instalar versión fijada, esperar salud y comprobar crear/suspender/snapshot S3/reanudar un actor mínimo.
- [ ] T051 [US3] Crear `infra/k8s/substrate/egress-policy.yaml` e `infra/scripts/check-egress.sh` para inyectar la credencial OpenAI real fuera del actor y probar un turno Codex a través del router sin exponerla en sandbox/logs, manifiestos versionados ni estado Terraform.
- [ ] T052 [US3] Crear `apps/control-plane/Dockerfile`, `apps/web/Dockerfile` e `infra/scripts/build-push.sh` para publicar imágenes reproducibles en ECR, verificar ausencia de credenciales en contextos/capas de build y registrar digest.
- [ ] T053 [US3] Crear `infra/k8s/apps/` con Deployment/Service privados de frontend y API, volumen SQLite, secreto de login, probes y recursos limitados.
- [ ] T054 [US3] Crear `infra/scripts/deploy.sh` que rehúse `terraform apply` sin reportes locales T017/T032, preflight T042, temporizador T043 y limpieza T044; luego instale Substrate, actor y apps y muestre `kubectl port-forward`.
- [ ] T055 [US3] Crear `infra/scripts/smoke-app.sh` para comprobar login, sesión, turno Codex, SSE y asignación real en EKS antes de declarar éxito.
- [ ] T056 [US3] Convertir `specs/001-substrate-agents-poc/quickstart.md` en runbook ejecutable con comandos reales locales y AWS, prerrequisitos, fallas, pérdida de sesiones y apagado.
- [ ] T057 [US3] Crear `infra/scripts/cost-audit.sh` para recuperar gasto AWS/OpenAI observado, indicar retrasos y escribir estimación/real/saldo por ventana en `infra/reports/cost-ledger.csv`.
- [ ] T058 [US3] Ejecutar dos ciclos EKS deploy/destroy/auditoría en `infra/reports/deployment-validation.md`; después del primero ejecutar T057, actualizar saldo y repetir solo si T042 aprueba la segunda ventana; ante falla ejecutar T044 y detenerse.

**Checkpoint**: EKS reproduce el flujo local y no quedan recursos inesperados tras cada ventana.

---

## Phase 6: User Story 4 — Controlar costos y límites (Priority: P4)

**Goal**: comparar estimación y gasto real, y decidir si otra ventana cabe dentro de USD 80.

**Independent Test**: estimar un escenario viable y otro inviable, comprobar alertas/temporizador y auditar el costo después del apagado.

- [X] T059 [US4] Crear `tests/contract/cost-estimate.spec.ts` con 730 horas, tarifas faltantes, gasto previo y presupuesto insuficiente; exigir rechazo del escenario no verificable.
- [ ] T060 [US4] Actualizar `specs/001-substrate-agents-poc/quickstart.md` con ejemplo regional medido, horas máximas, umbrales y verificación previa a nueva ventana.
- [ ] T061 [US4] Registrar una ventana corta con costo real, alertas, temporizador y residuos en `infra/reports/cost-validation.md`; bloquear otra si la proyección supera el saldo.

**Checkpoint**: existe evidencia de costo y control previo a cada ventana; las alertas no se presentan como límite duro.

---

## Phase 7: Polish & Cross-Cutting Concerns

- [ ] T062 Revisar `apps/control-plane/src/auth.ts`, `apps/codex-actor/src/server.ts` e `infra/k8s/` para evitar secretos en logs/SSE y limitar acceso a red, IAM y herramientas.
- [ ] T063 Ejecutar `tests/contract/` y `tests/e2e/` contra versión fijada y documentar SC-001 a SC-007, fallos y límites en `infra/reports/final-validation.md`.
- [ ] T064 Actualizar `README.md` con arquitectura, ruta local obligatoria, runbook EKS, costo y estado real de compatibilidad.
- [ ] T065 Revisar `specs/001-substrate-agents-poc/spec.md`, `plan.md`, `contracts/` e `infra/reports/final-validation.md` y registrar requisitos aún no cumplidos sin presentarlos como terminados.

## Dependencies & Execution Order

```text
Setup T001–T006
  → Local foundation T007–T018 (4 smoke tests individuales)
  → US1 T019–T032 (integración local real, gate antes de AWS)
  → US2 T033–T041 (chat local completo)
  → US3 T042–T058 (costo/cleanup antes del primer apply, luego EKS)
  → US4 T059–T061 (gasto observado y nueva ventana)
  → Polish T062–T065
```

- La primera ejecución autorizada de `deploy.sh` T054 ocurre en T058, tras verificar T017, T032 y T042–T044. T049–T057 crean scripts/manifiestos antes de ejecutarse; su ejecución en AWS forma parte del ciclo T058.
- Dentro de T019 se construye y carga la imagen local antes de registrar su plantilla; el flujo mínimo de solicitudes T022–T023 pertenece a US1 para que el MVP sea independiente.
- T044 precede cualquier recurso AWS, y T058 ejecuta destrucción y auditoría tras cada ciclo incluso ante error; T057 registra gasto antes de autorizar el segundo.

### Parallel Examples

- **Setup**: T002, T003 y T004 tocan workspaces distintos después de T001.
- **Local foundation**: T007 (kind), T010 (API), T013 (actor) y T016 (frontend) avanzan en archivos independientes; T017 espera los cuatro smoke tests.
- **US1**: T020 (cliente Substrate) y T028 (panel visual) pueden avanzar en paralelo tras el gate local individual; T021 espera T020, y T030 espera todos los flujos mínimos.
- **US2**: T033 (modelo) y T037 (UI) avanzan en paralelo; T034 espera T033.
- **US3**: T043 (alertas/temporizador) y T047 (S3/IAM) pueden construirse en paralelo; ningún recurso se crea antes de T054/T057.

## Implementation Strategy

1. Completar el mínimo local de los cuatro componentes y registrar sus smoke tests, sin AWS.
2. Integrar localmente con Substrate real y demostrar multiplexación; completar chat local y corregir fallas allí.
3. Antes de encender AWS, aprobar presupuesto, temporizador y limpieza. Repetir en EKS la misma imagen/contratos comprobados localmente.
4. Cerrar cada ventana con destrucción, auditoría y gasto observado; conservar los resultados de la PoC, no los recursos facturables.

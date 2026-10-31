# Tasks: PoC de Agent Substrate en EKS

**Input**: `specs/001-substrate-agents-poc/{spec,plan,research,data-model,quickstart}.md` y `contracts/`  
**Prerequisites**: rama `001-substrate-agents-poc`; acceso AWS/OpenAI solo para los gates que lo requieren.  
**Tests**: se incluyen verificaciones de integración y costo porque el plan exige probar compatibilidad, multiplexación y presupuesto. No se agregan pruebas que solo repliquen la implementación.  
**Organization**: [US1] multiplexación, [US2] chat, [US3] despliegue, [US4] costos. Cada tarea señala archivos concretos; los scripts listados se crearán durante la implementación.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: preparar el monorepo y fijar convenciones reproducibles.

- [ ] T001 Crear `package.json`, `pnpm-workspace.yaml` y `tsconfig.base.json` con workspaces `apps/web`, `apps/control-plane` y `apps/codex-actor`, Node.js 22 y comandos `build`, `lint` y `typecheck`.
- [ ] T002 [P] Crear `apps/web/package.json` y `apps/web/vite.config.ts` con React, TypeScript y proxy local `/api` hacia la API de chat.
- [ ] T003 [P] Crear `apps/control-plane/package.json` y `apps/control-plane/tsconfig.json` con Fastify, SQLite y build de imagen OCI.
- [ ] T004 [P] Crear `apps/codex-actor/package.json` y `apps/codex-actor/tsconfig.json` con adaptador HTTP y dependencias para ejecutar Codex app-server local.
- [ ] T005 [P] Crear `infra/terraform/versions.tf`, `infra/terraform/variables.tf` e `infra/terraform/outputs.tf` para región, versión EKS, duración, tamaño de nodos/pool y etiquetas de la PoC.
- [ ] T006 Crear `infra/config/example.env` y `.gitignore` para nombres de recursos y parámetros no secretos; excluir estado Terraform, SQLite, snapshots y credenciales del repositorio.

**Checkpoint**: workspaces y estructura compilan sin infraestructura AWS.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: demostrar que el entorno y Substrate pueden funcionar en EKS antes de construir experiencias que dependan de ello.

**Critical gate**: completar T007–T019 antes de las historias. Si un gate falla, T019 registra la causa y limpia recursos; las historias dependientes quedan detenidas hasta resolverlo.

- [ ] T007 Crear `infra/scripts/preflight-budget.sh` que exija gasto mensual observado, horas de ventana y tasas regionales de todas las categorías; calcule saldo de USD 80 con reserva del 20% y rechace un `apply` que lo supere.
- [ ] T008 Crear `infra/scripts/preflight-eks.sh` que verifique disponibilidad de EKS 1.37 en la región, cuotas y herramientas locales antes de `terraform apply`; escribir el resultado en `infra/reports/preflight.md`.
- [ ] T009 Crear `infra/terraform/network.tf` y `infra/terraform/eks.tf` con VPC/subred pública, endpoint EKS restringido, managed node group EC2 sin SSH, salida a Internet, etiquetas y sin NAT ni balanceador público.
- [ ] T010 [P] Crear `infra/terraform/storage-iam.tf` con bucket S3 de snapshots, roles de servicio para ambos sidecars y permisos mínimos al bucket/prefijo; impedir acceso público.
- [ ] T011 Registrar un tag o commit SHA inmutable de Agent Substrate y sus imágenes en `infra/substrate.lock`; explicar en `infra/README.md` cómo obtener exactamente esa versión.
- [ ] T012 Crear `infra/k8s/substrate/` con overlay de instalación que configure `ATE_STORAGE_BACKEND=s3` en sidecars de `atelet` y `ate-api-server`, identidad de ingreso autorizada, gVisor y WorkerPool de tamaño configurable (dos workers por defecto).
- [ ] T013 Crear `infra/k8s/smoke/pod-certificate.yaml` e `infra/scripts/check-pod-certificates.sh` para validar API discovery de `PodCertificateRequest`/`ClusterTrustBundle` y montaje real de `podCertificate` en EKS 1.37.
- [ ] T014 Crear `infra/scripts/install-substrate.sh` que aplique la versión fijada y el overlay, espere PostgreSQL, API, router, gateway, `atelet` y workers, y emita diagnóstico ante fallas.
- [ ] T015 Crear `infra/scripts/smoke-substrate.sh` que use un actor mínimo para crear, solicitar, suspender, confirmar snapshot S3 y reanudar, registrando actor y worker observados.
- [ ] T016 Crear `infra/scripts/check-egress.sh` e `infra/k8s/substrate/egress-policy.yaml` para probar salida a OpenAI mediante gateway e inyección de una credencial de prueba sin exponerla al actor ni a logs.
- [ ] T017 [P] Crear `apps/control-plane/src/server.ts` y `apps/control-plane/src/auth.ts` con servidor Fastify, `/api/healthz`, login de operador, cookie HttpOnly y validación de acceso a todas las rutas privadas.
- [ ] T018 [P] Crear `apps/control-plane/src/db/schema.sql` y `apps/control-plane/src/db/index.ts` con SQLite para sesiones, solicitudes y eventos, índices por sesión/solicitud y transiciones terminales únicas.
- [ ] T019 Crear `infra/scripts/gate-report.sh` e `infra/reports/gates.md` para registrar versiones, resultado de T008–T016, limitaciones EKS/S3/credenciales y limpieza inmediata si falla un gate.

**Checkpoint**: Substrate real en EKS crea/suspende/reanuda un actor, usa S3 y tiene ruta de egreso validada; la API local tiene base y autenticación. El costo de esta prueba queda dentro de una ventana aprobada por T007.

---

## Phase 3: User Story 1 — Observar la multiplexación de sesiones (Priority: P1) 🎯 MVP

**Goal**: tres sesiones tienen actores propios y muestran asignación, suspensión, reanudación y reutilización de workers reales.

**Independent Test**: con dos workers, crear tres sesiones, enviar turnos, suspender actores inactivos y confirmar en la UI que al menos dos actores distintos ocuparon el mismo worker en tiempos diferentes; repetir cinco ciclos conservando contexto.

- [ ] T020 [P] [US1] Crear `apps/codex-actor/Dockerfile` y `apps/codex-actor/config/` con binario Codex fijado, prompt de sistema, configuración MCP mínima y usuario de proceso sin privilegios innecesarios.
- [ ] T021 [US1] Implementar `apps/codex-actor/src/codex-client.ts` para iniciar app-server por stdio, crear/reanudar un hilo, iniciar turnos y mapear deltas y estado terminal real.
- [ ] T022 [US1] Implementar `apps/codex-actor/src/server.ts` con `POST /turns`, `GET /healthz`, deduplicación por `request_id`, rechazo de turno concurrente y eventos `started/delta/completed/failed` según `contracts/actor-http.md`.
- [ ] T023 [US1] Crear `infra/k8s/actor-template.yaml` y `infra/scripts/register-actor-template.sh` para publicar la imagen del actor como plantilla inmutable de Substrate y verificar su golden snapshot.
- [ ] T024 [P] [US1] Implementar `apps/control-plane/src/substrate/client.ts` para crear, consultar, suspender y eliminar actores mediante la API de Substrate, con errores tipados e identificadores correlacionables.
- [ ] T025 [US1] Implementar `apps/control-plane/src/sessions/service.ts` para mapear 1:1 sesión–actor en SQLite, crear/cerrar actores de forma idempotente y conservar `actor_id` estable.
- [ ] T026 [US1] Implementar `apps/control-plane/src/routes/sessions.ts` para `GET/POST /sessions` y `GET/DELETE /sessions/{sessionId}` según `contracts/openapi.yaml`.
- [ ] T027 [US1] Implementar `apps/control-plane/src/actor/router-client.ts` con cliente mTLS autorizado, cabecera `ate-target-actor`, timeout y retransmisión incremental desde el actor, sin asignar workers manualmente.
- [ ] T028 [US1] Implementar `apps/control-plane/src/events/store.ts` para persistir eventos con ID monotónico, `source`, hora y vínculos sesión–actor–worker; omitir secretos y prompts en eventos de topología.
- [ ] T029 [US1] Implementar `apps/control-plane/src/topology/service.ts` para obtener estados reales de actores/workers de Substrate, indicar datos desconocidos cuando falte observación y actualizar la vista en menos de cinco segundos.
- [ ] T030 [US1] Implementar `apps/control-plane/src/routes/topology.ts` con `GET /topology` y `GET /topology/events`, eventos SSE reanudables por `Last-Event-ID` y asignaciones solo tras confirmación de Substrate.
- [ ] T031 [US1] Implementar `apps/control-plane/src/sessions/idle-suspender.ts` para suspender solo actores sin turno activo tras el plazo configurado y registrar liberación del worker.
- [ ] T032 [P] [US1] Crear `apps/web/src/components/TopologyPanel.tsx` y `apps/web/src/components/Timeline.tsx` con estado libre/ocupado/no disponible, relación actor–worker y eventos fechados.
- [ ] T033 [US1] Crear `apps/web/src/pages/Dashboard.tsx` y `apps/web/src/api/client.ts` para crear tres sesiones, enviar un turno mínimo, ver deltas y enlazar el chat con la topología.
- [ ] T034 [US1] Crear `tests/e2e/multiplexing.spec.ts` que verifique con Substrate real 3 actores/2 workers, reutilización temporal de un worker y 5 ciclos suspend/resume con contexto conservado.
- [ ] T035 [US1] Ejecutar la prueba guiada de 30 minutos y documentar IDs, tiempos y evidencia de SC-001/SC-003 en `infra/reports/multiplexing.md`; marcar fallo si la UI muestra asignación no confirmada.

**Checkpoint**: MVP demostrable con agente Codex real y topología basada en Substrate.

---

## Phase 4: User Story 2 — Conversar con el agente (Priority: P2)

**Goal**: chats independientes con transmisión confiable, contexto aislado, espera por capacidad y recuperación de conexión.

**Independent Test**: dos sesiones alternan mensajes relacionados sin cruzar contexto; diez solicitudes entregan deltas y estado terminal o error explícito; una desconexión se recupera sin presentar texto parcial como completo.

- [ ] T036 [P] [US2] Implementar `apps/control-plane/src/requests/model.ts` con estados `queued/running/completed/failed/timed_out/cancelled`, un turno activo por sesión y clave de idempotencia.
- [ ] T037 [US2] Implementar `apps/control-plane/src/requests/service.ts` para persistir solicitud antes de enviarla, aplicar espera de capacidad configurable y registrar resultado terminal exactamente una vez.
- [ ] T038 [US2] Implementar `apps/control-plane/src/routes/requests.ts` con `POST /sessions/{sessionId}/requests`, `GET /requests/{requestId}` y `GET /requests/{requestId}/events` conforme al OpenAPI.
- [ ] T039 [US2] Implementar `apps/control-plane/src/events/sse.ts` con replay desde `Last-Event-ID`, heartbeats, backpressure y cierre tras `completed` o `failed`.
- [ ] T040 [US2] Asegurar en `apps/codex-actor/src/codex-client.ts` que el `thread_id` y los archivos de conversación sobreviven snapshot/reanudación y que cada actor usa un hilo propio.
- [ ] T041 [P] [US2] Crear `apps/web/src/components/ChatPanel.tsx` y `apps/web/src/hooks/useRequestEvents.ts` con historial por sesión, deltas, espera, errores y reconexión que consulta el estado final.
- [ ] T042 [US2] Crear `apps/codex-actor/config/mcp.json` y `apps/codex-actor/config/system-prompt.md` con servidores MCP permitidos y políticas de herramienta acordes a la PoC; documentar configuración en `apps/codex-actor/README.md`.
- [ ] T043 [US2] Crear `tests/contract/chat-api.spec.ts` para validar estados, códigos HTTP y formato/replay SSE del contrato, usando un actor simulado y sin repetir la lógica interna.
- [ ] T044 [US2] Crear `tests/e2e/chat-isolation.spec.ts` para comprobar continuidad dentro de una sesión y aislamiento entre dos actores tras suspensión/reanudación.
- [ ] T045 [US2] Crear `tests/e2e/chat-reconnect.spec.ts` para cortar SSE durante un turno, reconectar con `Last-Event-ID` y verificar que `GET /requests/{id}` distingue respuesta parcial de terminada.

**Checkpoint**: experiencia de chat completa con estados verificables y aislamiento de sesión.

---

## Phase 5: User Story 3 — Desplegar y apagar la PoC (Priority: P3)

**Goal**: un operador puede crear, verificar, destruir y recrear todos los componentes sin pasos ocultos.

**Independent Test**: desde una cuenta preparada, seguir el runbook, obtener conversación y topología, destruir y auditar recursos, luego recrear y repetir; medir 90 minutos para encender/verificar y 20 para apagar/auditar.

- [ ] T046 [P] [US3] Crear `apps/control-plane/Dockerfile`, `apps/web/Dockerfile` e `infra/scripts/build-push.sh` para construir imágenes reproducibles, publicarlas en ECR y registrar digest en `infra/reports/images.md`.
- [ ] T047 [US3] Crear `infra/k8s/apps/` con Deployment/Service del frontend y API, volumen SQLite, secretos de login, probes y recursos limitados; no crear Ingress ni LoadBalancer públicos.
- [ ] T048 [US3] Crear `infra/scripts/deploy.sh` que ejecute T007–T016, aplique T023/T047, espere readiness y muestre el comando de `kubectl port-forward` para el operador.
- [ ] T049 [US3] Implementar `infra/scripts/smoke-app.sh` para comprobar login, creación de sesión, turno Codex, SSE y evento de asignación visible antes de declarar éxito.
- [ ] T050 [US3] Crear `infra/scripts/destroy.sh` que deje de aceptar turnos, elimine actores/volúmenes/objetos S3 de la PoC y ejecute `terraform destroy` en orden seguro, con salida no cero ante falla parcial.
- [ ] T051 [US3] Crear `infra/scripts/audit-residuals.sh` que enumere por etiquetas EKS, EC2, EBS, ELB, NAT, IP públicas, S3, ECR y logs remanentes y su posible cargo.
- [ ] T052 [US3] Convertir `specs/001-substrate-agents-poc/quickstart.md` en runbook ejecutable con comandos y variables reales, prerequisitos, gates, solución de fallas, pérdida de sesiones y secuencia de reencendido.
- [ ] T053 [US3] Ejecutar dos ciclos de deploy/destroy en AWS y registrar versiones, duración, pruebas, recursos remanentes y límites de SC-004 en `infra/reports/deployment-validation.md`.
- [ ] T054 [US3] Crear `infra/scripts/verify-cleanup.sh` que falle si T051 detecta recursos facturables inesperados y dejar constancia de `cleanup_failed` en `infra/reports/deployment-validation.md`.

**Checkpoint**: flujo completo reproducible y limpieza verificada, con sesiones efímeras declaradas.

---

## Phase 6: User Story 4 — Controlar costos y límites (Priority: P4)

**Goal**: estimación y avisos antes de consumir USD 80, con gasto observado y auditoría de residuos.

**Independent Test**: introducir región, ventana y consumo previsto; verificar desglose y rechazo de un escenario sobre presupuesto; disparar umbrales de prueba y comprobar auditoría tras apagado.

- [ ] T055 [US4] Crear `infra/scripts/cost-estimate.ts` que obtenga o exija tarifas regionales vigentes y desglosa EKS, nodos, IPv4, EBS, red, S3, logs y tokens OpenAI; calcula horas máximas con gasto previo y reserva del 20%.
- [ ] T056 [P] [US4] Crear `infra/terraform/budget.tf` con alertas AWS Budgets a USD 40 y USD 70, destinatario configurable y etiquetas de la PoC; documentar retraso de actualización.
- [ ] T057 [US4] Crear `infra/scripts/stop-timer.sh` que programe el apagado local para `planned_stop_at`, avise antes y ejecute o solicite `destroy.sh` según el modo configurado, registrando resultado.
- [ ] T058 [US4] Crear `infra/scripts/cost-audit.sh` que recupere gasto AWS observado y consumo OpenAI disponible, señale retrasos de datos y compare estimación/real/saldo por ventana en `infra/reports/cost-ledger.csv`.
- [ ] T059 [US4] Crear `tests/contract/cost-estimate.spec.ts` con escenarios de 730 horas, tarifas faltantes, gasto previo y presupuesto insuficiente; verificar que jamás se declara seguro un costo desconocido.
- [ ] T060 [US4] Actualizar `specs/001-substrate-agents-poc/quickstart.md` con ejemplo regional medido, duración máxima recomendada y pasos de verificación antes de repetir una ventana.
- [ ] T061 [US4] Ejecutar una ventana corta y registrar cargos reales, alertas, temporizador y residuos en `infra/reports/cost-validation.md`; si la proyección excede el saldo, no iniciar otra.

**Checkpoint**: el operador dispone de estimación, temporizador, alertas y costo observado; no se promete que AWS Budgets actúe como límite duro.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: cerrar riesgos transversales y dejar evidencia revisable.

- [ ] T062 Revisar `apps/control-plane/src/auth.ts`, `apps/codex-actor/src/server.ts` e `infra/k8s/` para impedir secretos en logs/SSE, limitar acceso de red y verificar que el actor no recibe credencial OpenAI real.
- [ ] T063 Ejecutar `tests/contract/` y `tests/e2e/` contra la versión fijada, documentar fallos y resultados de SC-001 a SC-006 en `infra/reports/final-validation.md`.
- [ ] T064 Actualizar `README.md` con arquitectura, enlace al runbook, prerequisitos, costos, encendido/apagado y estado real de compatibilidad EKS.
- [ ] T065 Revisar `specs/001-substrate-agents-poc/spec.md`, `plan.md`, `contracts/` y `infra/reports/final-validation.md` para señalar requisitos no cumplidos y decisiones de seguimiento sin presentarlos como completados.

## Dependencies & Execution Order

### Phase Dependencies

```text
Setup (T001–T006)
  → Foundation (T007–T019)
  → US1 MVP (T020–T035)
  → US2 chat completo (T036–T045)
  → US3 despliegue operable (T046–T054)
  → US4 costos completos (T055–T061)
  → Polish (T062–T065)
```

- El **gate de presupuesto T007 precede todo `terraform apply`**. T008–T016 prueban EKS/Substrate; si fallan, ejecutar T019 y no continuar despliegues pagados.
- T017 y T018 pueden desarrollarse localmente junto con el gate; sus archivos no dependen entre sí. T020/T024/T032 pueden comenzar después del foundation porque tocan componentes distintos.
- US1 entrega el MVP y satisface la demostración principal. US2 depende del actor/API mínimos de US1 para mejorar chat. US3 integra los artefactos de US1/US2; su infraestructura básica se crea en foundation. US4 puede diseñarse desde foundation, pero la validación de costo real requiere al menos una ventana de US3.
- La prueba T034 precede el registro de evidencia T035. T049 precede la declaración de despliegue exitoso; T050/T051/T054 deben ejecutarse al final de cada ventana, incluso después de falla.

### Parallel Examples

- **Setup**: T002 (frontend), T003 (API), T004 (actor) y T005 (Terraform) son archivos separados después de T001.
- **Foundation**: T010 (IAM/S3), T017 (servidor/auth local) y T018 (schema SQLite) pueden avanzar en paralelo después de T001/T005, sin ejecutar AWS antes de T007.
- **US1**: T020 (imagen de actor), T024 (cliente Substrate) y T032 (panel visual) usan archivos separados tras foundation; T021 espera T020, y T025 espera T024/T018.
- **US2**: T036 (modelo de solicitud) y T041 (componentes visuales) son independientes tras US1; T037 espera T036, T038 espera T037.
- **US3**: T046 (imágenes) puede avanzar junto con documentación preliminar T052; T048 espera imágenes, manifiestos y gates.
- **US4**: T056 (alertas Terraform) puede avanzar en paralelo con T055 (estimador); T058 requiere una ventana real para registrar gasto observado.

## Implementation Strategy

1. **MVP primero**: completar setup, foundation y US1; detenerse y verificar que tres actores comparten dos workers con suspensión/reanudación real. Si EKS/Substrate falla, registrar el bloqueo y limpiar sin construir una simulación engañosa.
2. **Incrementos**: agregar US2 para chat robusto, US3 para operación repetible y US4 para control financiero. Revalidar el MVP tras cada integración.
3. **Ventanas pagadas**: realizar la mayor parte del desarrollo y pruebas con mocks/localmente; encender EKS solo con presupuesto aprobado y tiempo de apagado definido. Cada ventana termina con `destroy`, auditoría y registro de costo.

## Notes

- `[P]` solo indica archivos y dependencias independientes; no autoriza desplegar simultáneamente recursos compartidos.
- Los checks de AWS/OpenAI exigen credenciales del operador y generan cargos; se ejecutan solo durante ventanas aprobadas por el preflight.
- La constitución del proyecto sigue siendo una plantilla sin principios ratificados; el plan no introduce gates constitucionales adicionales.

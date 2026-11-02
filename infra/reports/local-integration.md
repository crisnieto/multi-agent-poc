# Integración local con Substrate real

Fecha de ejecución: 2026-11-02 UTC. Versión Substrate: `0f7ebfa3061cc37f6897ec40a130660994259631`. Imagen Codex registrada por digest en `codex-poc`; modelo fijado: `gpt-6-luna`, esfuerzo `none`.

| Verificación | Evidencia | Resultado |
|---|---|---|
| Cuatro componentes individuales | `infra/reports/local-components.md` | PASS, 4/4 |
| Egreso seguro | `infra/local/check-egress.sh`: clave ausente de plantilla, archivos y logs inspeccionados; actor con marcador | PASS |
| Integración HTTP/SSE | `infra/local/smoke-integrated.sh`: frontend servido, API real, turno Codex, deltas, `completed`, worker observado, suspensión y reanudación | PASS |
| Topología e inactividad | `infra/local/smoke-topology.sh`: dos workers, actor asignado, uno ocupado, suspensión automática y ambos libres | PASS |
| Multiplexación y contexto | `tests/e2e/multiplexing.spec.ts`, datos crudos en `infra/reports/local-multiplexing.json` | PASS en prueba de 30,2 s |
| Ventana sostenida SC-001 | `tests/e2e/multiplexing-soak.spec.ts`, muestras en `infra/reports/local-soak.jsonl` | PASS, 42 min 23 s, 5 muestras, 0 llamadas OpenAI |

La prueba de multiplexación creó tres sesiones y actores distintos sobre dos workers. A las 00:07:31.846Z, los dos primeros ocuparon workers diferentes (`de693cec-8777-40d9-88ab-f2f729d87606` y `d23e93bc-32bf-452a-88ad-4695a6746b68`). Tras liberar el primero, el tercero usó el mismo worker a las 00:07:35.925Z. Entre 00:07:36.788Z y 00:07:47.821Z, cada actor completó cinco ciclos de suspensión y reanudación; luego cada sesión recuperó su animal de prueba sin mezclar contexto. Los tres actores se eliminaron al finalizar.

La interfaz fue verificada en Chrome local: login, sesión, turno con respuesta `listo`, worker ocupado, actor asignado y worker libre al cerrar el chat. La UI mostró el ID de worker obtenido de Substrate, no una asignación simulada. No se creó ningún recurso AWS.

La prueba sostenida empezó a las 00:09:43.596Z y terminó a las 00:52:06.877Z (2.543.281 ms). En las cinco muestras, tres sesiones utilizaron dos workers; se observó que el tercer actor reutilizaba el worker liberado en cada muestra. La API de topología confirmó dos workers ocupados durante cada secuencia. No hubo llamadas a OpenAI durante esta ventana.

**SC-001**: reutilización observada y visible durante más de 30 minutos, aprobada. **SC-003**: cinco ciclos por actor y contexto aislado aprobados; la liberación del worker se observó en la prueba de topología. **SC-007**: cuatro componentes individuales y ciclo integrado aprobados.

Gate local previo a AWS: **PASS**. La creación de recursos AWS sigue bloqueada hasta implementar y aprobar el preflight financiero y el flujo de destrucción/auditoría.

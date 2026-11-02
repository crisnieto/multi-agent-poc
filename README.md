# PoC de Agent Substrate

Monorepo de una PoC con cuatro componentes: interfaz de chat y topología (`apps/web`), API de sesiones y SSE (`apps/control-plane`), actor Codex (`apps/codex-actor`) y gestión de workers con [Agent Substrate](https://github.com/agent-substrate/substrate). Una sesión corresponde a un actor; Substrate decide qué worker ejecuta cada turno.

## Estado

- **Local:** los cuatro componentes y la integración real con Substrate pasaron sus pruebas. La [guía de prueba](specs/001-substrate-agents-poc/quickstart.md) explica cómo arrancar la demo y apagarla. La [evidencia local](infra/reports/local-integration.md) incluye sesiones, suspensión, reanudación y multiplexación.
- **AWS:** el primer `terraform apply` creó EKS, pero la instalación de Substrate se detuvo por una validación GCS incompatible con S3. El overlay ya corrige esa validación y el despliegue no se ha reintentado. La [evidencia del intento](infra/reports/eks-attempt-2026-11-02.md) registra el cierre. La aplicación en EKS aún no se ha validado. El acceso por DNS público asignado por AWS es opcional, HTTP y está desactivado por defecto.

## Presupuesto y seguridad

El límite es **USD 80 mensuales incluyendo AWS y OpenAI**. El clúster base estimado en `us-east-1` cuesta USD 0,2554/h antes de almacenamiento, registros, tráfico y tokens; por eso se requieren ventanas cortas con destrucción completa. `infra/scripts/preflight-budget.sh` rechaza tarifas faltantes, una lectura de gasto OpenAI de más de 24 horas o una proyección que no deje 20 % de reserva. Las alertas de AWS Budgets informan el consumo, pero no apagan recursos.

La clave `OPENAI_API_KEY` se pasa solo en ejecución. Nunca se guarda en un archivo versionado ni en una imagen. `scripts/check-secrets.sh` y los hooks de Git revisan los cambios antes de commit y push. Consultar [quickstart](specs/001-substrate-agents-poc/quickstart.md) para la preparación local y los gates de AWS.

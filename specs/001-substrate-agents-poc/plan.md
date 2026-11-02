# Implementation Plan: PoC de Agent Substrate en EKS

**Branch**: `001-substrate-agents-poc` | **Date**: 2026-10-31 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `specs/001-substrate-agents-poc/spec.md`

## Summary

Construir una PoC de cuatro piezas: interfaz de chat y topología, API de chat, actor Codex y gestión de Substrate. Primero, cada pieza arranca y supera un smoke test local por separado; después, una integración local con Substrate real demuestra chat, asignación, suspensión y reanudación. Solo con ese gate aprobado se despliega temporalmente en EKS 1.37 con S3 y nodos EC2. Una sesión crea un actor y Substrate decide su worker. La destrucción completa al terminar cada ventana limita el gasto de AWS.

## Technical Context

**Language/Version**: TypeScript con Node.js 22 para API y adaptador del actor; TypeScript para frontend; shell y Terraform para automatización. Las versiones exactas se fijan en lockfiles e imágenes al implementar.  
**Primary Dependencies**: React/Vite, Fastify, Codex app-server, Agent Substrate fijado a tag/commit, Docker y kind para desarrollo local, Kubernetes/EKS, Terraform, AWS CLI, kubectl.
**Storage**: SQLite en volumen de la ventana para sesiones y eventos; PostgreSQL propio de Substrate para actores/workers; S3 para snapshots; todo se elimina al apagar.  
**Testing**: smoke test independiente de los cuatro componentes; contratos API con dependencias simuladas; integración local con kind, Substrate real y almacenamiento local compatible; smoke test EKS de certificados/S3; prueba de extremo a extremo con 3 sesiones/2 workers y 5 ciclos suspend/resume.
**Target Platform**: desarrollo local en máquina con Docker/kind (incluido macOS mediante la VM de Docker, sujeto a recursos suficientes); destino EKS 1.37 con managed node group EC2 y workers gVisor; navegador de escritorio del operador.
**Project Type**: monorepo web + API + imagen de actor + infraestructura.  
**Performance Goals**: primer evento visible en menos de 10 s sin saturación; topología actualizada en menos de 5 s; 3 sesiones con 2 workers para la demostración.  
**Constraints**: presupuesto mensual total USD 80 incluyendo OpenAI; acceso restringido, sin LB/NAT; una réplica de API y sin alta disponibilidad; efímero entre ventanas; streaming y credenciales fuera del actor sujetos a gate.  
**Scale/Scope**: un operador o pequeño grupo, una región, un clúster temporal, una plantilla de actor Codex, configuración MCP acotada.

## Constitution Check

La `.specify/memory/constitution.md` actual es una plantilla sin principios ratificados. No hay gates normativos aplicables. Antes de Phase 0 y tras Phase 1: **PASS**; no se infieren reglas a partir de placeholders.

## Design Decisions

- **Dos planos de control**: la API propia administra chats y observabilidad; `ate-api-server` de Substrate administra actores, workers y snapshots. La API propia no asigna pods manualmente.
- **Identidad**: `session_id` se mapea 1:1 a `actor_id`, guardado en SQLite. La API consulta el estado real de Substrate para la topología y guarda eventos con sello de tiempo y origen; nunca presenta un dato inferido como medición real.
- **Flujo**: `POST /sessions` crea el actor; `POST /sessions/{id}/requests` inicia turno; `GET /requests/{id}/events` entrega SSE con IDs reanudables; `GET /topology` consulta un snapshot; `GET /topology/events` transmite cambios. El backend usa el router de Substrate con identidad permitida y cabecera de destino.
- **Inactividad**: el backend solicita suspensión solo tras turno finalizado y plazo configurable; cuando el actor está ocupado, difiere la suspensión. La siguiente petición activa la reanudación normal de Substrate.
- **Autenticación**: acceso por port-forward y login de PoC con contraseña cargada como secreto, sesión HTTP segura en localhost; API y actor no son públicos. La clave OpenAI no se escribe en archivos versionados, commits, pushes, imágenes ni logs. En el actor standalone local se entrega solo al proceso; en kind y EKS se resuelve en el gateway de egreso y el actor recibe únicamente un marcador no sensible, si el gate lo valida. `.gitignore` y verificaciones antes de commit/push son defensa adicional.
- **Errores y capacidad**: estado de solicitud durante la ventana, espera acotada de capacidad, eventos de error tipados, SSE con `Last-Event-ID`; los eventos `done` solo siguen a finalización real.
- **Infraestructura**: Terraform crea red, EKS, managed node group, roles IAM, bucket S3 y presupuesto/alertas. Manifiestos versionados instalan Substrate, pool, API y frontend. Tamaño configurable; sin autoscaling complejo inicial. `destroy` elimina recursos y audita residuos.
- **Desarrollo local**: `apps/web` arranca con datos simulados; `apps/control-plane` arranca con SQLite y rutas mínimas sobre adaptadores simulados; `apps/codex-actor` expone HTTP y app-server local con un turno real de costo acotado; `infra/local` levanta kind, Substrate y un actor de prueba. Un smoke test por componente precede a la integración local con los cuatro. Allí el gateway local inyecta la clave fuera del actor. La integración usa la misma imagen y contratos que EKS, y registra evidencia sin AWS.

## Phase 0 — Research and gates

Las decisiones, fuentes y alternativas están en [research.md](research.md). La implementación comenzará con el gate local individual y después el integrado con Substrate real. Ningún `terraform apply` de AWS se permite antes de aprobar ambos, comprobar presupuesto y disponer de limpieza automática. Luego se valida EKS/S3/certificados y se repite el flujo de extremo a extremo. Si falla un gate, se registra la causa; el presupuesto se calcula por región y horas antes de aprovisionar.

## Phase 1 — Design and contracts

- [data-model.md](data-model.md): sesiones, solicitudes, eventos, actores, workers y ventanas de prueba, con transiciones y retención.
- [contracts/openapi.yaml](contracts/openapi.yaml): API del frontend y formato SSE.
- [contracts/actor-http.md](contracts/actor-http.md): contrato API propia ↔ actor y reglas de transmisión/errores.
- [quickstart.md](quickstart.md): orden de preparación local por componente, integración local, gates AWS, despliegue, demostración, costos y destrucción.

**Post-design Constitution Check**: PASS; la constitución sigue sin principios ratificados. La complejidad adicional se justifica por los cuatro componentes solicitados y la necesidad de verificar multiplexación real.

## Project Structure

### Documentation (this feature)

```text
specs/001-substrate-agents-poc/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
└── contracts/
    ├── openapi.yaml
    └── actor-http.md
```

### Source Code (repository root)

```text
apps/
├── web/                 # chat, workers, timeline
├── control-plane/       # sesiones, Substrate adapter, SSE, SQLite
└── codex-actor/         # imagen OCI, HTTP adapter, app-server, prompt/MCP
infra/
├── local/               # kind, Substrate local, almacenamiento y smoke tests
├── terraform/           # VPC, EKS, node group, S3, IAM, budget
├── k8s/                 # overlays Substrate, WorkerPool, apps
└── scripts/             # preflight, deploy, verify, destroy, cost audit
tests/
├── contract/
└── e2e/
```

**Structure Decision**: monorepo con los tres componentes propios separados y la gestión de Substrate/infraestructura bajo `infra/`. No se duplican los componentes upstream de Substrate.

## Complexity Tracking

No hay violaciones constitucionales que registrar; la constitución está sin ratificar.

# Investigación y decisiones

Fecha: 2026-10-31. Estas decisiones se basan en documentación; la instalación completa en EKS aún requiere una prueba real.

## R0. Gate local obligatorio antes de AWS

**Decisión**: iniciar y verificar por separado frontend, API, actor Codex y Substrate en un clúster local kind; luego probar los cuatro integrados con Substrate real. La [guía de desarrollo oficial de Substrate](https://github.com/agent-substrate/substrate#quickstart-development) incluye creación de clúster kind, instalación del sistema, actor de ejemplo y limpieza. Se fijará un commit y se usarán sus comandos/overlays correspondientes, pues la interfaz del proyecto cambia.

**Fundamento**: separa errores de cada componente de los problemas específicos de EKS y evita cargos AWS durante el ciclo inicial. El frontend y la API pueden arrancar con adaptadores simulados; el actor debe demostrar un turno real acotado con Codex y OpenAI, y Substrate debe demostrar al menos el actor de ejemplo. La prueba integrada no usa mocks para Substrate.

**Alternativas**: ejecutar solo pruebas con mocks no valida la multiplexación; empezar directamente en EKS expone el presupuesto a fallas de desarrollo. La ejecución local en macOS depende de la VM Linux de Docker y recursos suficientes; el gate debe informar limitaciones de host sin considerarlas fallas de EKS.

## R1. Compatibilidad de Substrate con EKS

**Decisión**: usar EKS con Kubernetes 1.37 en soporte estándar y ejecutar un gate de compatibilidad antes de instalar el resto. El gate verifica mediante API discovery `PodCertificateRequest` y `ClusterTrustBundle`, monta un volumen `podCertificate`, instala el plano de Substrate y comprueba que sus componentes estén listos.

**Fundamento**: Kubernetes 1.37 hizo estables estas capacidades y EKS ofrece 1.37. Substrate usa certificados de pod en sus componentes. No se encontró un quickstart oficial de Substrate en EKS; disponibilidad de versión no equivale a integración probada. [Kubernetes 1.37](https://kubernetes.io/blog/2026/08/26/kubernetes-v1-37-release/), [versiones EKS](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html), [instalación Substrate](https://github.com/agent-substrate/substrate/blob/main/docs/guides/operator-install.md).

**Alternativas**: GKE tiene ruta documentada, pero no satisface AWS EKS; Kubernetes autogestionado en EC2 pierde EKS administrado. Si el gate falla, detener la PoC EKS y registrar el bloqueo, sin sustituir silenciosamente el objetivo.

## R2. Snapshots y estado

**Decisión**: usar el plugin oficial de Substrate con backend S3 para snapshots, configurado tanto en `atelet` como en `ate-api-server`; rol IAM restringido al bucket/prefijo de la PoC. PostgreSQL del sistema guarda el estado de actores/workers. En cada apagado de bajo costo se eliminan clúster, base y snapshots: las sesiones se consideran efímeras entre ventanas.

**Fundamento**: el plugin actual admite `s3://` y `ATE_STORAGE_BACKEND=s3`, aunque los manifiestos base predeterminan GCS. El plugin S3 usa credenciales del pod y no aplica la misma restricción por actor que GCS; el alcance del rol IAM debe quedar documentado. [Plugin de objetos](https://github.com/agent-substrate/substrate/blob/main/cmd/objectstore-plugin/README.md), [arquitectura](https://github.com/agent-substrate/substrate/blob/main/docs/concepts/architecture.md).

**Alternativas**: GCS añade dependencia entre nubes; retener S3 y base entre apagados mantiene costo residual y no es necesario para la demostración inicial.

## R3. Runtime y nodos

**Decisión**: usar workers gVisor y nodos EC2 en un managed node group; iniciar con dos workers de Substrate y ajustar capacidad EC2 tras medir solicitudes reales. No usar Fargate para Substrate.

**Fundamento**: `atelet` es DaemonSet con privilegios y acceso de host; los workers requieren el runtime de sandbox. Dos workers permiten observar reasignación, aunque tres actores con un worker también demuestran reutilización. [Manifiesto de atelet](https://github.com/agent-substrate/substrate/blob/main/manifests/ate-install/atelet.yaml), [cómputo EKS](https://docs.aws.amazon.com/eks/latest/userguide/eks-compute.html).

**Alternativas**: microVM añade requisitos de virtualización y costo; Fargate no proporciona el acceso al host necesario.

## R4. Integración del agente Codex

**Decisión**: una imagen OCI contiene un adaptador HTTP pequeño y Codex app-server local por stdio. Cada actor mantiene un hilo Codex y su estado local; el adaptador traduce el flujo de eventos del app-server a un flujo HTTP que el servicio de chat retransmite como SSE. El sistema prompt y una lista acotada de MCP se versionan con la imagen/configuración. Se usa una clave de proyecto OpenAI para facturación medible.

**Fundamento**: la [documentación oficial de OpenAI Docs para app-server](https://learn.chatgpt.com/docs/app-server) describe hilos, turnos, eventos y conexión local; el [SDK Codex](https://learn.chatgpt.com/docs/codex-sdk) es alternativa más simple para scripts. La autenticación de la aplicación con API key requiere prueba con la política de egreso de Substrate; el objetivo es que el gateway inyecte credenciales y el actor no las conserve. [Inyección de credenciales de Substrate](https://github.com/agent-substrate/substrate/blob/main/docs/guides/egress-credential-injection.md).

**Alternativas**: Codex SDK reduce código de protocolo pero da menos control del ciclo de conversación; llamadas directas a Responses no ejecutarían el harness Codex requerido. El gate de integración probará app-server, streaming, MCP y egreso antes del frontend.

## R5. Transporte y asignación

**Decisión**: navegador envía mensajes con `POST`; observa eventos con `GET` SSE. El control plane de la PoC crea un actor por sesión y lo enruta mediante `atenet-router` con identidad autorizada y `ate-target-actor`. Substrate administra las asignaciones, no la aplicación. Eventos de topología se derivan del estado real de Substrate y se correlacionan con las sesiones.

**Fundamento**: SSE es unidireccional. El router de Substrate reanuda actores y los dirige a workers. Deben probarse explícitamente transmisión incremental y mTLS por el router. [Arquitectura Substrate](https://github.com/agent-substrate/substrate/blob/main/docs/concepts/architecture.md), [streaming OpenAI](https://developers.openai.com/api/docs/guides/streaming-responses).

**Alternativas**: WebSocket extremo a extremo añade complejidad sin necesidad en la PoC; asignación manual a pods falsificaría la propiedad que se quiere evaluar.

## R6. Presupuesto y exposición

**Decisión**: despliegues por ventanas, sin balanceador público ni NAT Gateway. Acceso de operador por `kubectl port-forward`; nodos en subred pública con salida a Internet y grupos de seguridad sin ingreso público de aplicación. Un temporizador local de apagado complementa AWS Budgets. Antes de crear recursos, estimar la ventana con precios regionales actuales y reservar 20% del presupuesto para incertidumbre.

**Fundamento**: EKS estándar cuesta USD 0,10/h, o USD 73 en 730 horas solo por el clúster; nodos, IPv4, discos y modelo se cobran aparte. NAT y balanceadores tienen cargos fijos; AWS Budgets puede actualizarse con retraso y no es un tope duro. [EKS](https://aws.amazon.com/eks/pricing/), [VPC](https://aws.amazon.com/vpc/pricing/), [ELB](https://aws.amazon.com/elasticloadbalancing/pricing/), [Budgets](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html).

**Alternativas**: EKS siempre encendido incumple el presupuesto; balanceador o NAT facilitan acceso/red privada pero consumen una parte significativa de USD 80. Los nodos públicos son solo para esta PoC restringida y deben revisarse con sus políticas de seguridad.

## Gates que deben medirse antes de la implementación completa

1. Arranque y smoke test local individual de frontend, API, actor Codex y Substrate; registrar cuatro resultados.
2. Integración local con Substrate real: sesión, turno incremental, asignación observada, suspensión y reanudación.
3. Antes de AWS: estimación regional menor que saldo disponible, temporizador y ruta de destrucción/auditoría listos.
4. EKS 1.37 en la región seleccionada; API discovery y montaje de certificados de pod; instalación, salud, S3 e IAM.
5. En EKS: actor de prueba y actor Codex con streaming, contexto tras snapshot, MCP y credencial inyectada fuera del actor.

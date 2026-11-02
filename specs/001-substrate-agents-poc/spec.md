# Feature Specification: PoC de Agent Substrate en EKS

**Feature Branch**: `001-substrate-agents-poc`  
**Created**: 2026-10-31  
**Status**: Draft  
**Input**: PoC con frontend de chat y visualización de pods, control plane con respuestas en tiempo real, agente Codex, gestión de Agent Substrate, despliegue reproducible en AWS EKS y presupuesto máximo de USD 80.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Observar la multiplexación de sesiones (Priority: P1)

Como evaluador, quiero crear varias sesiones de chat, enviar mensajes a agentes y ver qué actor y worker atienden cada solicitud, cuándo un worker queda libre y cuándo una sesión suspendida se reanuda. Así puedo comprobar el comportamiento de multiplexación de Substrate con evidencia observable.

**Why this priority**: Es la hipótesis principal de la PoC.

**Independent Test**: Crear tres sesiones con un pool menor de workers, enviar solicitudes en distintos momentos y comprobar la secuencia de asignación, suspensión y reutilización sin confundir sesiones.

**Acceptance Scenarios**:

1. **Given** un pool con workers disponibles, **When** se crea una sesión y se envía un mensaje, **Then** aparece un actor exclusivo de esa sesión, el worker asignado, su estado y la respuesta incremental en el chat.
2. **Given** una sesión cuyo actor terminó de trabajar, **When** vence el tiempo de inactividad configurado o se solicita su suspensión, **Then** el actor figura suspendido y el worker vuelve a estar disponible.
3. **Given** un actor suspendido y un worker libre, **When** llega otro mensaje a la misma sesión, **Then** se reanuda el mismo actor con su contexto y se muestra su nueva asignación, que puede ser otro worker.
4. **Given** más sesiones que workers, **When** se atienden solicitudes secuenciales, **Then** el historial permite verificar que distintos actores usaron un mismo worker en momentos diferentes.

---

### User Story 2 - Conversar con el agente (Priority: P2)

Como usuario de la PoC, quiero abrir chats independientes y recibir la respuesta del agente a medida que se genera, para probar el recorrido completo desde la interfaz hasta el proveedor del modelo.

**Why this priority**: Confirma que la multiplexación corresponde a trabajo real del agente.

**Independent Test**: Abrir una sesión, enviar dos mensajes relacionados y comprobar continuidad contextual y entrega incremental; abrir otra y verificar aislamiento de contexto.

**Acceptance Scenarios**:

1. **Given** una sesión nueva, **When** el usuario envía un mensaje, **Then** ve progreso y una respuesta completa o un error entendible.
2. **Given** dos sesiones activas, **When** el usuario intercala mensajes, **Then** cada conversación conserva su propio historial y actor, sin compartir mensajes ni contexto.
3. **Given** una respuesta en curso, **When** se interrumpe la conexión de la interfaz, **Then** el estado final de la solicitud puede consultarse y la interfaz no muestra una respuesta parcial como completa.

---

### User Story 3 - Desplegar y apagar la PoC (Priority: P3)

Como operador, quiero levantar cada componente por separado en mi equipo, integrarlos localmente y solo después levantar, verificar, apagar y volver a levantar el conjunto en EKS mediante un procedimiento documentado. Así puedo detectar fallas sin consumir infraestructura AWS durante el desarrollo inicial.

**Why this priority**: El presupuesto impide mantener el entorno aprovisionado de forma continua.

**Independent Test**: Arrancar y verificar localmente frontend, API de chat, actor Codex y Substrate por separado; completar una conversación y una asignación en la integración local; luego repetir el despliegue, apagado y recreación en EKS desde una cuenta preparada.

**Acceptance Scenarios**:

1. **Given** una máquina de desarrollo preparada, **When** el operador sigue la guía local, **Then** puede iniciar y verificar cada uno de los cuatro componentes por separado en su capacidad mínima, sin crear recursos AWS.
2. **Given** los cuatro componentes verificados por separado, **When** el operador ejecuta la integración local, **Then** una sesión completa un turno y muestra el actor y worker reales de Substrate local.
3. **Given** el gate local aprobado y los prerrequisitos de AWS, **When** el operador sigue la guía EKS, **Then** obtiene un entorno funcional con los mismos componentes o un diagnóstico explícito de incompatibilidad verificable.
4. **Given** el entorno EKS en funcionamiento, **When** el operador ejecuta el procedimiento de apagado, **Then** se eliminan los recursos de cómputo y el clúster, se enumeran los recursos persistentes y se informa su costo residual estimado.
5. **Given** el entorno EKS apagado, **When** el operador lo vuelve a levantar, **Then** se recrean los componentes y se puede repetir la demostración sin pasos manuales no documentados.

---

### User Story 4 - Controlar costos y límites (Priority: P4)

Como responsable del presupuesto, quiero conocer el costo estimado antes de encender el entorno y recibir señales para apagarlo antes de agotar USD 80, incluyendo infraestructura y uso del modelo.

**Why this priority**: Evita que una PoC exploratoria siga generando cargos inadvertidos.

**Independent Test**: Revisar una estimación con duración y carga declaradas, comprobar umbrales y verificar el inventario de recursos después del apagado.

**Acceptance Scenarios**:

1. **Given** una duración de prueba y una región, **When** se prepara el despliegue, **Then** la guía muestra el costo estimado por categoría, las suposiciones y las horas máximas sugeridas para el presupuesto.
2. **Given** que el gasto observado o proyectado se acerca al límite, **When** alcanza los umbrales configurados, **Then** el operador recibe avisos y tiene un procedimiento inmediato de apagado.

### Edge Cases

- Si no hay worker libre, la solicitud muestra espera y termina con respuesta o error por tiempo de espera; no se pierde ni se asigna a otro actor.
- Si falla el agente, el proveedor del modelo o una herramienta MCP, la sesión conserva un estado coherente y el usuario recibe un error distinguible de una respuesta terminada.
- Si se solicita suspensión mientras hay una respuesta activa, el sistema evita cortar la respuesta y deja constancia de cuándo se libera el worker.
- Si una sesión se elimina o expira, se libera su actor y se define el destino de su estado y costos de almacenamiento.
- Si Substrate no puede instalarse o funcionar en la versión elegida de EKS, el procedimiento detiene el despliegue con evidencia y sin dejar recursos facturables innecesarios.
- Si falta un prerrequisito local o un componente no arranca, el gate local indica cuál falló y no habilita el despliegue AWS.
- Si el apagado es parcial, el inventario identifica clúster, nodos, balanceadores, discos, direcciones, almacenamiento y registros que sigan generando cargos.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: El sistema MUST permitir crear y distinguir sesiones de chat independientes; cada sesión MUST mantener una relación estable con un actor de Substrate hasta su cierre.
- **FR-002**: El sistema MUST permitir enviar mensajes y mostrar la respuesta del agente de forma incremental, junto con estados de pendiente, en curso, finalizada y fallida.
- **FR-003**: El servicio de chat MUST recibir solicitudes del frontend, dirigirlas al actor de la sesión y transmitir al frontend los eventos de respuesta sin mezclar sesiones.
- **FR-004**: El agente MUST usar la configuración definida para Codex, incluidas instrucciones de sistema y herramientas MCP habilitadas para la prueba, y MUST poder comunicarse con el proveedor OpenAI.
- **FR-005**: El sistema MUST conservar el contexto de conversación dentro de una sesión durante ciclos de suspensión y reanudación del actor; MUST impedir que ese contexto aparezca en otra sesión.
- **FR-006**: La interfaz MUST mostrar el estado de cada sesión y actor, el worker o pod actual cuando exista, y los estados de cada worker: libre, ocupado o no disponible.
- **FR-007**: La interfaz MUST mostrar eventos con hora y relación sesión–actor–worker para creación, asignación, inicio de trabajo, fin de trabajo, suspensión, reanudación, liberación y error.
- **FR-008**: El sistema MUST permitir demostrar con al menos tres sesiones y menos workers que sesiones la reutilización de un worker por diferentes actores en momentos distintos.
- **FR-009**: El sistema MUST permitir configurar el tamaño del pool y la política de inactividad para observar la multiplexación en pruebas repetibles.
- **FR-010**: El sistema MUST informar al usuario cuando una solicitud espera capacidad y MUST aplicar un límite de espera configurable con resultado explícito.
- **FR-011**: El sistema MUST autenticar el acceso de operador a la PoC y MUST proteger las credenciales del proveedor y de las herramientas. La clave OpenAI MUST quedar fuera del repositorio, commits, pushes, imágenes, manifiestos versionados, interfaz y eventos; dentro de Substrate MUST inyectarse fuera del actor cuando el mecanismo lo permita.
- **FR-012**: El proyecto MUST incluir un procedimiento reproducible para preparar AWS EKS, instalar y configurar Substrate, publicar y desplegar los otros tres componentes, verificar salud y ejecutar la demostración de extremo a extremo.
- **FR-013**: El procedimiento MUST verificar previamente los requisitos de compatibilidad de la versión fijada de Substrate con EKS, incluidos los servicios de identidad, almacenamiento de estado y capacidades de clúster necesarios; MUST registrar cualquier adaptación o limitación.
- **FR-014**: El proyecto MUST incluir procedimientos reproducibles de apagado y reencendido que identifiquen dependencias, recursos persistentes, pérdida esperada de datos y cargos residuales.
- **FR-015**: El proyecto MUST proporcionar una estimación de costo para la región y ventana de prueba elegidas, separando clúster, capacidad de cómputo, red, almacenamiento, observabilidad y consumo del modelo.
- **FR-016**: El proyecto MUST incluir umbrales de aviso de gasto, una duración máxima recomendada por ventana de prueba y un método para comprobar el gasto real y los recursos remanentes antes de repetirla.
- **FR-017**: El sistema MUST registrar errores de creación, enrutamiento, suspensión y reanudación de actores con identificadores correlacionables a la sesión y la solicitud, sin registrar secretos ni contenido sensible por defecto.
- **FR-018**: La documentación MUST describir explícitamente qué estado de sesiones se conserva al apagar el entorno y cómo se limpia al cerrar la prueba.
- **FR-019**: Antes de cualquier despliegue en AWS, el proyecto MUST permitir iniciar y verificar de forma independiente, en un entorno local sin recursos AWS, el frontend, el servicio de chat, el actor Codex y la gestión de Substrate; MUST proporcionar una prueba local integrada de chat, asignación y suspensión/reanudación que registre el resultado de cada componente.

### Key Entities *(include if feature involves data)*

- **Sesión de chat**: Conversación independiente; incluye identificador, historial, estado, actor asignado y horas de creación/cierre.
- **Actor de agente**: Instancia con estado asignada a una sesión; incluye identificador, plantilla o versión, estado de ciclo de vida y último worker conocido.
- **Worker o pod**: Capacidad física del pool que hospeda temporalmente un actor; incluye identificador, disponibilidad y actor actual.
- **Solicitud de chat**: Mensaje enviado dentro de una sesión; incluye identificador, estado, secuencia de eventos y resultado o error.
- **Evento de asignación**: Cambio fechado del vínculo entre sesión, actor y worker, usado para demostrar multiplexación.
- **Ventana de prueba**: Período de entorno encendido; incluye región, hora de inicio y fin, presupuesto, estimación y gasto observado.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Un evaluador puede crear tres sesiones y demostrar, mediante eventos visibles, que al menos dos actores diferentes usan el mismo worker en momentos distintos durante una prueba de 30 minutos.
- **SC-002**: En 10 conversaciones de prueba, al menos 9 muestran respuesta incremental y finalización o error explícito, sin mezclar mensajes entre sesiones.
- **SC-003**: En cinco ciclos de suspensión y reanudación, el contexto de cada sesión se conserva en los cinco y el worker vuelve a libre después de cada suspensión completada.
- **SC-004**: Un operador puede levantar y verificar el entorno siguiendo la guía en menos de 90 minutos después de cumplir los prerrequisitos; puede apagarlo y comprobar los recursos remanentes en menos de 20 minutos.
- **SC-005**: La guía permite planificar ventanas de prueba cuyo costo mensual total estimado no supera USD 80 para las condiciones declaradas; el gasto real se compara con ese límite al terminar cada ventana.
- **SC-006**: En una revisión guiada, el operador puede explicar el recorrido de una solicitud y localizar la sesión, el actor y el worker que la atendieron en menos de 2 minutos.
- **SC-007**: Los cuatro componentes superan sus verificaciones locales individuales y una conversación integrada completa un ciclo de asignación, suspensión y reanudación antes de la primera creación de recursos AWS.

## Assumptions

- La PoC es de acceso restringido a un operador o pequeño grupo de evaluadores; no se requiere un producto multiusuario público.
- El límite de USD 80 se interpreta como presupuesto mensual total de la prueba para infraestructura AWS y consumo del proveedor de modelo, según uso y precios de la región elegida; no implica disponibilidad continua. Los importes exactos se validarán en planificación.
- El entorno se encenderá durante ventanas breves. “Apagar” incluye eliminar el clúster y recursos asociados que sigan cobrando; únicamente pueden permanecer recursos persistentes inventariados y aceptados para la siguiente ventana.
- Las sesiones pueden ser efímeras al eliminar el entorno; sí deben conservar contexto durante suspensión y reanudación dentro de una ventana de prueba.
- La compatibilidad de Substrate con EKS y con almacenamiento e identidad disponibles en AWS es una hipótesis técnica que se comprobará antes de comprometer el despliegue completo.
- El alcance inicial incluye una configuración acotada de herramientas MCP, sin exigir una lista concreta de servidores ni permisos de terceros.
- El intercambio de mensajes del usuario usa solicitudes hacia el servicio de chat y entrega incremental de eventos hacia la interfaz; el detalle de transporte se define en el plan.
- La versión de Substrate se fijará para la PoC porque el proyecto aún puede cambiar sus interfaces y requisitos.
- La ruta local usará un clúster Kubernetes de desarrollo compatible con la versión fijada de Substrate; los componentes propios podrán arrancar también por separado con dobles de prueba para sus dependencias. La prueba integrada local usará Substrate real.

# Guía de despliegue y prueba

`infra/local` ya permite verificar los cuatro componentes por separado y la integración local con Substrate real. La evidencia está en `infra/reports/local-components.md` y `infra/reports/local-integration.md`; ambos gates locales pasaron. Terraform, el overlay S3/AL2023, el build de imágenes, el pool y los manifiestos privados de aplicaciones están preparados. Los contenedores `amd64` de API y web se construyeron y respondieron por HTTP localmente. **No se ha ejecutado `terraform apply` ni se ha verificado la integración EKS real.** El commit de Substrate está fijado en `infra/substrate.lock`.

## Activación futura de la ventana AWS (no ejecutar hasta indicación del operador)

1. Con el operador, confirmar una lectura reciente de OpenAI Billing y refrescar las tarifas de `infra/config/prices.us-east-1.example.json` si tienen más de siete días. Copiar el archivo a `infra/.runtime/aws/prices.us-east-1.json` (ignorado por Git) y actualizar `priced_at` solo después de verificar los precios. El ejemplo fija una ventana de seis horas, un nodo `t3a.xlarge`, dos workers, USD 80 de límite y 20 % de reserva. La lectura del 2 de noviembre (OpenAI USD 0,03, AWS USD 1,1488) produjo una proyección conservadora de USD 15,646 para la ventana; debe recalcularse antes del `apply`.
2. Crear `infra/terraform/poc.tfvars` desde `poc.tfvars.example` con la IP pública actual del operador y el correo de AWS Budgets. El archivo real queda ignorado por Git. Instalar dependencias con `pnpm install`, disponer de Docker buildx, Go, Terraform, AWS CLI y kubectl. En Apple Silicon, el build `linux/amd64` local necesitó Colima con `--vz-rosetta`.
3. Cargar `POC_OPERATOR_PASSWORD` en el entorno sin eco, conservar `OPENAI_API_KEY` solo en el entorno, y establecer `POC_AWS_REGION`, `POC_TFVARS`, `POC_PRICE_FILE`, `POC_PRIOR_OPENAI_SPEND_USD` y `POC_OPENAI_SPEND_AS_OF_UTC`. No poner ninguna clave en el archivo de variables, en Terraform ni en el comando.
4. Solo tras una instrucción explícita de levantar AWS, invocar `POC_DEPLOY_APPROVED=1 infra/scripts/deploy.sh`. El script exige los gates locales, consulta EKS y Cost Explorer, calcula el presupuesto, coteja horas/nodos/región contra el plan, crea el clúster, arma un temporizador de seis horas, instala Substrate, publica imágenes por digest, configura egreso y despliega las aplicaciones. Ante error posterior al `apply`, ejecuta `destroy.sh`.
5. Ejecutar `infra/scripts/smoke-app.sh`, abrir `kubectl -n ate-system port-forward svc/poc-web 8080:8080` y probar tres sesiones/dos workers. Al terminar, ejecutar `infra/scripts/destroy.sh` y `infra/scripts/verify-cleanup.sh`. El temporizador local exige que este equipo permanezca encendido; AWS Budgets no es un límite duro. Registrar gasto real antes de otra ventana.

**Estado actual:** la orden explícita del operador es mantener AWS apagado. Los scripts de activación no se han ejecutado; EKS/S3/PodCertificates, RBAC del cliente embebido y el flujo real Codex en EKS aún deben validarse durante la primera ventana. Si falla cualquier gate, destruir y registrar el fallo antes de reintentar.

## Comandos locales ya implementados

### Demo interactiva completa

Con `OPENAI_API_KEY` ya disponible en el shell, el clúster kind instalado y la imagen/pool Codex preparados, ejecutar desde la raíz:

```bash
infra/local/start-demo.sh
```

En macOS, el script registra la API y Vite en `launchd`; permanecen activos al cerrar el terminal. Abrir `http://127.0.0.1:5173/?mode=real`, ingresar con `local-poc-only` (o el valor de `POC_OPERATOR_PASSWORD` si se configuró), crear un **Nuevo chat** y enviar un mensaje. El panel de la derecha muestra los pods `codex-poc`, su estado Libre/Ocupado, el actor asignado y la actividad. Esperar aproximadamente 60 segundos tras un turno para observar la suspensión automática. Una petición posterior reanuda el actor. Para mostrar multiplexación, crear tres chats: los dos primeros pueden ocupar los dos workers; al suspender o cerrar uno, el tercero puede usar el worker liberado. Cada turno real consume créditos mínimos de OpenAI con `gpt-6-luna`.

```bash
infra/local/stop-demo.sh          # Detiene API/web y borra el Secret OpenAI; conserva kind.
infra/local/verify-cleanup.sh     # Después de stop-demo, elimina kind y registro local.
colima stop -p substrate-poc      # Opcional: libera la VM Docker.
```

Los logs y la base SQLite de la demo quedan en `infra/.runtime/local-demo/`, ignorado por Git. `start-demo.sh` no entrega la clave OpenAI a la API ni a Vite; el gateway la toma de un Secret local. En Linux los procesos se inician con `nohup` y dependen de que la sesión de usuario permita procesos persistentes.

Desde la raíz del repositorio:

```bash
git config --local core.hooksPath .githooks
pnpm install
pnpm build
infra/local/smoke-web.sh
POC_OPERATOR_PASSWORD='una-contraseña-local-temporal' infra/local/smoke-control-plane.sh
```

Para Substrate en macOS, iniciar una VM Docker con al menos 8 GiB disponibles, Go, `kubectl` y Docker `buildx` en PATH. El script crea el cluster `kind` y el registro `kind-registry` sin AWS:

```bash
colima start -p substrate-poc --cpu 4 --memory 10 --disk 60
infra/local/up.sh
infra/local/install-substrate.sh
infra/local/smoke-substrate.sh
infra/local/verify-cleanup.sh
colima stop -p substrate-poc
```

El smoke real del actor exige una clave de API de un proyecto OpenAI Platform, disponible en el [panel de claves](https://platform.openai.com/api-keys). `apps/codex-actor/config/config.toml` configura a Codex para leer `OPENAI_API_KEY` desde el entorno del proceso mediante `env_key`, sin iniciar sesión ni guardar la clave en `auth.json`. Escribirla sin eco en el terminal y ejecutar la prueba desde ese mismo shell; nunca incluirla en un archivo o argumento de línea de comandos:

```bash
read -rs OPENAI_API_KEY
export OPENAI_API_KEY
infra/local/smoke-codex-actor.sh
unset OPENAI_API_KEY
```

`infra/local/verify-components.sh` ejecuta los cuatro smoke tests y escribe `infra/reports/local-components.md`. Si falta la clave o falla cualquier componente, reporta FAIL y el gate permanece cerrado. El 1 de noviembre de 2026 pasaron los cuatro componentes, incluido un turno real del actor con `gpt-6-luna` y razonamiento `none`. El gate de integración local pasó el 2 de noviembre; AWS aún requiere su propio preflight y pruebas.

La integración local usa el gateway de Substrate para sustituir el marcador del actor por la clave real. Con el clúster arriba, ejecutar desde un shell que tenga `OPENAI_API_KEY` solo en su entorno:

```bash
infra/local/build-load-actor.sh
infra/local/prepare-egress.sh
infra/local/check-egress.sh
infra/local/smoke-integrated.sh
infra/local/smoke-topology.sh
pnpm --filter @poc/control-plane exec tsx ../../tests/e2e/multiplexing.spec.ts
infra/local/clear-egress.sh
```

`prepare-egress.sh` crea un Secret de Kubernetes a través de stdin; la imagen y la plantilla solo contienen `substrate-placeholder`. `clear-egress.sh` borra ese Secret al terminar. `smoke-integrated.sh` arranca frontend y API locales, completa un turno Codex y comprueba SSE, asignación, suspensión y reanudación. Para abrir el dashboard manualmente, arrancar API en `POC_SUBSTRATE_MODE=real` y Vite, y visitar `http://127.0.0.1:5173/?mode=real`. La prueba sostenida de 42 minutos sin llamadas OpenAI figura en `infra/reports/local-soak.jsonl`.

## Presupuesto previo a AWS

El [cargo estándar de EKS](https://aws.amazon.com/eks/pricing/) es USD 0,10/h. En us-east-1, [t3a.xlarge](https://aws.amazon.com/ec2/instance-types/t3/) figura a USD 0,1504/h y una [IPv4 pública](https://aws.amazon.com/vpc/pricing/) cuesta USD 0,005/h. Esta base de USD 0,2554/h suma USD 186,44 en 730 horas, antes de EBS, S3, registros, transferencia y OpenAI. La `t3a.xlarge` conserva 4 vCPU y 16 GiB en x86 por menor costo que la `t3.xlarge`. [La prueba local con 8 GiB](../../infra/reports/local-sizing.md) pasó en memoria con dos workers, pero el total de solicitudes de CPU del clúster kind fue 2,11 vCPU; `t3a.large` solo dispone de 2 vCPU. El ahorro EC2 de una ventana de 48 horas sería USD 3,61, de modo que se mantiene el tamaño de 4 vCPU hasta validar una configuración menor en EKS. ARM requeriría verificar todas las imágenes. El límite de USD 80 exige ventanas temporales y destrucción al cerrar cada una.

`infra/config/prices.example.json` deja en `null` las tarifas que aún hay que comprobar. `infra/scripts/cost-estimate.ts` rechaza tarifas desconocidas o de más de siete días, y `preflight-budget.sh` exige gasto AWS actual desde Cost Explorer y gasto OpenAI leído en las últimas 24 horas. Se reserva al menos 20 % del presupuesto. El ejemplo falla deliberadamente hasta completar las tarifas; no habilita despliegue.

`infra/terraform/poc.tfvars.example` también tiene IP y correo ficticios que Terraform rechaza. Guardar la configuración real como `infra/terraform/poc.tfvars` (ignorado por Git). `infra/scripts/stop-timer.sh arm 48` crea un proceso local que llama a `destroy.sh` al vencer la ventana; `stop-timer.sh status` permite comprobarlo. Este proceso necesita que el equipo permanezca encendido y con conectividad: no es una garantía contra un corte de energía o la suspensión del equipo. `destroy.sh` requiere `POC_TFVARS` y `POC_AWS_REGION`, elimina PVC antes de Terraform y ejecuta `audit-residuals.sh`. La StorageClass `substrate-poc-gp3` etiqueta los EBS para hacerlos auditables. `tests/infra/cleanup.spec.sh` probó estado ausente, estado limpio, EBS residual y rechazo de proyecto incorrecto con AWS simulado. No hay evidencia todavía de destrucción en una cuenta AWS real.

## Etapa previa obligatoria: ejecución local sin AWS

1. Preparar Docker, kind, `kubectl`, Go y Node.js según el commit fijado de Substrate. Activar los hooks versionados con `git config --local core.hooksPath .githooks` en cada clon y comprobar la verificación de secretos antes de un commit/push. En macOS, kind y los workers corren en la VM Linux de Docker; comprobar memoria y arquitectura de imágenes antes de iniciar. Usar la [ruta oficial de desarrollo local de Substrate](https://github.com/agent-substrate/substrate#quickstart-development) correspondiente al commit fijado.
2. **Frontend**: iniciar `apps/web` con un adaptador de datos de demostración. Abrir la página, crear un chat de ejemplo y visualizar estados de worker simulados, claramente identificados como datos de prueba. No requiere API, OpenAI ni AWS.
3. **Control plane de chat**: iniciar `apps/control-plane` con SQLite local y un actor/Substrate simulados. Comprobar `/api/healthz`, crear una sesión, enviar un mensaje, recibir SSE y cerrar la sesión. No requiere frontend, OpenAI ni AWS.
4. **Actor Codex**: iniciar `apps/codex-actor` por separado. Comprobar `/healthz` y `POST /turns` con respuesta incremental y estado terminal. Para el turno real se usa una clave OpenAI de desarrollo con límite de gasto, entregada solo como variable del proceso. No escribirla en `.env`, comandos registrados, archivos, logs, imágenes, commits ni pushes. La prueba integrada con Substrate local valida la inyección por gateway. No requiere frontend, API de chat ni AWS.
5. **Gestión Substrate**: levantar el clúster kind y el sistema Substrate del commit fijado, más almacenamiento local compatible y un actor de ejemplo. Comprobar workers libres, asignación, suspensión, snapshot y reanudación. No requiere los tres componentes propios ni AWS.
6. **Integración local**: configurar el gateway de egreso para inyectar la clave OpenAI fuera del actor, comprobar que el sandbox y los logs no la contienen, conectar frontend y API al Substrate local, registrar la imagen del actor Codex en el registro local y completar una sesión real con turnos, asignación visible, suspensión y reanudación. Registrar resultados de los cinco pasos en un reporte de gate local. Si alguno falla, detener aquí y no iniciar AWS.
7. Apagar los procesos propios, el clúster kind, el registro y el almacenamiento local; verificar que no queda un entorno de prueba activo. La guía de AWS comienza únicamente con el reporte local aprobado.

## 0. Prerrequisitos y presupuesto para AWS

1. Confirmar que el reporte de gate local tiene los cuatro smoke tests individuales y la integración aprobados y que la verificación de secretos del repositorio pasa. Preparar cuenta AWS aislada o etiquetas exclusivas para la PoC, permiso para EKS, EC2, VPC, IAM, ECR, S3, EBS y AWS Budgets. Proyecto OpenAI con límite de uso y clave API; no guardar claves en Git.
2. Instalar Terraform, AWS CLI, `kubectl`, herramienta de construcción OCI y el CLI de Substrate correspondiente al commit fijado.
3. Elegir región donde EKS 1.37 esté disponible, por defecto `us-east-1` sujeto a verificación. Revisar cuotas de EC2, IP públicas y EKS.
4. Introducir horas máximas de la ventana y gasto ya consumido en el mes. `cost-preflight` deberá obtener precios regionales actuales y calcular:

   `estimación = horas × (EKS + nodos + IPv4 + volúmenes + red fija) + almacenamiento/transferencia/logs + tokens OpenAI previstos + margen`

   El presupuesto operativo para nuevas ventanas es `USD 80 − gasto mensual observado − reserva de 20%`. Si la estimación supera ese saldo, no desplegar. La tasa de EKS estándar es USD 0,10/h; 730 h equivalen a USD 73 antes de otros cargos. Ver [precios EKS](https://aws.amazon.com/eks/pricing/).
5. Configurar avisos a USD 40 y USD 70, un temporizador local con hora de apagado y una alarma independiente para la clave OpenAI. Los avisos de AWS Budgets pueden retrasarse; el temporizador es el control inmediato, no un límite financiero infalible. [AWS Budgets](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html).

## 1. Preparar infraestructura

1. `deploy` llama a Terraform para crear VPC/subredes, EKS 1.37, managed node group EC2, ECR, S3, roles IAM y alertas. La configuración inicial evita NAT Gateway y balanceador público; los nodos necesitan salida a Internet mediante la subred pública y grupos de seguridad restringidos. No habilitar SSH. El endpoint de EKS se limita al IP del operador cuando sea posible.
2. Crear los roles para los dos sidecars del plugin S3 de Substrate. Limitar operaciones de objeto al bucket/prefijo de snapshots; documentar que S3 no restringe cada transferencia por actor del mismo modo que GCS.
3. Provisionar almacenamiento de PostgreSQL de Substrate y SQLite de la API. Antes de destruir el entorno se eliminarán sus volúmenes; no se persisten sesiones entre ventanas.

## 2. Gate EKS/Substrate

1. Confirmar con `aws eks describe-cluster` que la versión es 1.37 y los nodos están listos.
2. Comprobar con API discovery que `podcertificaterequests` y `clustertrustbundles` existen en `certificates.k8s.io/v1`; ejecutar un pod de prueba que monte `podCertificate` y revisar eventos de montaje.
3. Instalar la versión fijada de Substrate y sus CRD. Aplicar el overlay EKS que configura ambos sidecars de almacenamiento con `ATE_STORAGE_BACKEND=s3`, bucket, región y rol IAM. Instalar PostgreSQL, router, egress gateway, `atelet` y WorkerPool gVisor de dos workers.
4. Esperar readiness de API, router, gateway, `atelet`, PostgreSQL y workers. Si falla, registrar eventos/logs, destruir recursos y detener el flujo. La existencia de EKS 1.37 por sí sola no demuestra compatibilidad.
5. Ejecutar un actor mínimo: crear, enviar petición, suspender, comprobar snapshot S3, reanudar y observar la asignación. Repetir hasta comprobar un cambio de worker o documentar por qué no pudo forzarse de forma segura.

## 3. Gate Codex y despliegue de aplicaciones

1. Construir/publicar la imagen del actor con adaptador HTTP, Codex app-server, prompt y MCP permitidos. Crear plantilla inmutable de actor en Substrate.
2. Configurar el egress gateway para OpenAI y MCP aprobados; inyectar clave de OpenAI fuera del actor. Probar una llamada real de Codex. Si el harness no funciona con la inyección, detenerse y documentar la limitación de seguridad antes de continuar.
3. Probar `POST /turns` del actor a través de `atenet-router` con identidad SPIFFE autorizada: deben llegar deltas, evento terminal, continuidad del hilo tras snapshot y errores tipados.
4. Instalar la API de chat y el frontend. Acceder solo con `kubectl port-forward` al servicio del frontend/API y hacer login de operador. No publicar un `LoadBalancer` ni Ingress público para esta PoC.

## 4. Demostración y verificación

1. Crear tres sesiones. La UI muestra tres `actor_id` diferentes y dos workers del mismo pool.
2. Enviar turnos y observar `queued → running → completed`, deltas en el chat, `worker.busy` y `actor.assigned` con hora.
3. Esperar inactividad o solicitar suspensión tras el turno, verificar `actor.suspended` y `worker.idle`.
4. Reanudar la primera sesión; comprobar memoria conversacional, evento de reanudación y asignación real. Repetir cinco ciclos y guardar una captura o exportación de eventos.
5. Desconectar SSE a mitad de un turno y reconectar con `Last-Event-ID`; consultar `GET /requests/{id}` para evitar etiquetar una respuesta parcial como completa.
6. Comparar el gasto real de AWS y OpenAI con la estimación y el saldo restante antes de una nueva ventana.

## 5. Apagar, auditar y volver a encender

1. Detener nuevas solicitudes. Finalizar o cancelar turnos activos; exportar solo los eventos de demostración sin secretos si se necesitan.
2. `destroy` elimina actores, despliegues, volúmenes, node group y clúster mediante Terraform; vacía y elimina el bucket S3 y repositorios ECR creados para la PoC, salvo artefactos que el operador haya elegido conservar y contabilizar.
3. `cost-audit` lista recursos con etiquetas de la PoC y verifica EKS, EC2, EBS, load balancers, NAT, IP públicas, S3, ECR y logs. Reporta cualquier residuo con costo potencial; una eliminación parcial deja estado `cleanup_failed` y exige corrección.
4. Para reencender, repetir desde el paso 0 con nueva ventana y saldo actualizado. Las sesiones anteriores se pierden deliberadamente; la configuración declarativa recrea todos los componentes.

## Criterios de salida

La guía solo se considera validada cuando el flujo completo se ejecuta en una cuenta AWS de prueba y se registran región, versión/digest de Substrate, tipo y número de nodos, duración, estimación, gasto observado y resultado del gate. Hasta entonces, los tiempos de despliegue y la cifra total bajo USD 80 son objetivos, no resultados medidos.

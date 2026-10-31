# Guía de despliegue y prueba planeada

Esta guía define el flujo que deben implementar `infra/terraform`, `infra/k8s` e `infra/scripts`. **Los scripts aún no existen**; no se debe ejecutar la PoC en AWS hasta implementar y revisar los gates. Todas las versiones e imágenes se fijarán a tag/digest en la implementación.

## 0. Prerrequisitos y presupuesto

1. Cuenta AWS aislada o etiquetas exclusivas para la PoC, permiso para EKS, EC2, VPC, IAM, ECR, S3, EBS y AWS Budgets. Proyecto OpenAI con límite de uso y clave API; no guardar claves en Git.
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

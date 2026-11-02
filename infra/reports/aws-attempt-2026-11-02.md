# Intento de despliegue AWS — 2026-11-02 02:58 UTC

**Resultado:** bloqueado antes de `terraform apply`; no se crearon recursos AWS para esta PoC.

- El preflight read-only de `infra/scripts/preflight-eks.sh` pasó en `us-east-1`: EKS 1.37 en soporte estándar, addon EBS CSI, oferta `t3a.xlarge` en al menos dos AZ y cuota disponible de 4 vCPU.
- Cost Explorer devolvió USD 1,1487743815 de gasto AWS acumulado para noviembre al momento de la consulta. Es un dato con posible retraso de facturación y no sustituye el cálculo completo de la ventana.
- `preflight-budget.sh` rechazó la ejecución por falta de una lectura actual del gasto OpenAI API (`POC_PRIOR_OPENAI_SPEND_USD` y `POC_OPENAI_SPEND_AS_OF_UTC`). El correo de alertas ya fue proporcionado por el operador, pero no cambia este gate.
- `infra/config/prices.example.json` contiene tarifas `null` de EBS, S3, ECR, CloudWatch y transferencia. Por diseño, el estimador las rechaza hasta verificarlas para la región y registrar sus fuentes.
- La instalación EKS aún carece del overlay S3/gVisor completo y los manifiestos/imágenes para API y frontend; `quickstart.md` y `tasks.md` los registran como pendientes. Crear solo el clúster no satisfaría el objetivo de levantar los cuatro componentes.

**Siguiente paso:** completar la integración EKS y las tarifas; obtener la lectura OpenAI API actual; ejecutar de nuevo ambos preflights y un `terraform plan` antes del primer `apply`. Mantener ventanas cortas, temporizador activo y destrucción auditada.

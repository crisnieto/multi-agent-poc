# Primer intento EKS — 2026-11-02

- Región: `us-east-1`; ventana máxima: 2 horas desde el comienzo de `terraform apply`.
- Preflight financiero: AWS observado USD 1,1488; OpenAI informado USD 0,03; estimación de la ventana USD 13,3891; proyección acumulada USD 14,5678 frente al límite operativo USD 64 (reserva de 20 % sobre USD 80). La cifra AWS observada es anterior a este intento; la facturación final puede tardar en aparecer.
- `terraform apply` creó EKS 1.37, un nodo `t3a.xlarge`, addons, S3, ECR, IAM y presupuesto. El instalador de Substrate falló antes de desplegar las aplicaciones: `RequireTransferServiceAccount` exigía `storage.transferGSAName` incluso con `--snapshot-location=s3://...`.
- `deploy.sh` activó la destrucción automática. El operador pidió expresamente no reintentar el despliegue.
- Corrección preparada: el overlay EKS omite el requisito GCS solo para ubicaciones S3; las pruebas comprueban que GCS sigue exigiéndolo. Se agregó una opción HTTP de web pública con DNS asignado por AWS, desactivada por defecto y sin recursos creados en este intento.

Estado de limpieza: `terraform destroy` eliminó los 57 recursos creados. La auditoría incluida en `destroy.sh` y una segunda ejecución de `verify-cleanup.sh` encontraron estado Terraform 0 y cero EKS, VPC, instancias EC2 activas, EBS, NAT, IPv4 elásticas, ECR, S3, logs EKS y balanceadores. El temporizador local quedó desarmado tras el fallo y antes de la destrucción automática. No quedó un despliegue activo de esta PoC.

EKS/Substrate y la aplicación completa no fueron validados. El gasto final debe revisarse en Cost Explorer antes de autorizar otra ventana.

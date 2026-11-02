# Preparación AWS sin despliegue — 2026-11-02

**Instrucción vigente:** no crear ni iniciar recursos AWS. No se ejecutaron `terraform apply`, `build-push.sh`, `install-substrate.sh` ni `deploy.sh`. No hay `terraform.tfstate` local. El clúster kind local ya fue eliminado; Colima se apagó tras las pruebas de imagen.

## Preparado

- `infra/scripts/deploy.sh` exige `POC_DEPLOY_APPROVED=1`, gates locales aprobados, preflight EKS, cálculo de costo actual, plan con seis horas/un nodo/dos workers y presupuesto AWS Budgets. Ante fallo posterior al `apply`, intenta destrucción. El flag de activación no se ha usado.
- `prepare-substrate-eks.sh` aplica S3 a ambos plugins de Substrate del commit fijado y rutas ECR de AL2023 a `atelet` en un worktree ignorado por Git. Kustomize renderizó ese worktree.
- `install-substrate.sh` instala gVisor, snapshot `s3://<bucket>/`, PostgreSQL sobre EBS gp3, gateway y API; `check-pod-certificates.sh` exige API discovery y un montaje real de certificado antes de continuar.
- `build-push.sh` compila `kubectl-ate` para Linux/amd64 y publica actor, API, web y worker en ECR por digest. `deploy-apps.sh` crea dos workers, plantilla Codex, Secrets por stdin, política de egreso y servicios privados. `smoke-app.sh` prueba un turno real y SSE cuando exista el clúster.
- `.dockerignore` excluye cache/runtime, estado Terraform, variables y archivos de secretos. Los hooks de Git revisan claves antes de commit/push.

## Evidencia local de preparación

- `pnpm typecheck`, `pnpm build`, `terraform validate` y `bash -n` pasaron.
- El manifiesto de aplicaciones se parseó como diez documentos YAML; no se pudo validar contra la API de Kubernetes sin arrancar un clúster.
- Docker construyó `poc-web:local` y `poc-control-plane:local` para `linux/amd64` con Rosetta local. La web sirvió `/` y la API respondió `/api/healthz` en modo simulado. Las imágenes locales miden aproximadamente 26 MB y 117 MB. No se hizo push.
- Un `terraform plan` anterior, sin aplicar, mostró 57 recursos nuevos con IP del operador restringida y seis horas. Se guarda ignorado en `infra/.runtime/aws/`.
- Con gasto OpenAI declarado de USD 0,03 y gasto AWS observado por Cost Explorer de USD 1,1488, el preflight estimó USD 14,4672 para seis horas y USD 15,6460 acumulados. Límite operativo con reserva del 20 %: USD 64. Las tarifas y el gasto deben refrescarse antes de cualquier `apply`.

## Gates pendientes de la primera ventana

EKS real aún debe demostrar soporte de PodCertificate/ClusterTrustBundle, identidad y permisos del cliente `kubectl-ate` embebido, snapshots en S3, egreso OpenAI fuera del actor y multiplexación con dos workers. Si alguno falla, el script de activación intenta destruir la ventana; confirmar `verify-cleanup.sh` y el gasto observado. El temporizador es local y requiere la computadora encendida, por lo que no se presenta como límite financiero automático garantizado.

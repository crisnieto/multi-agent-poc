#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_command kubectl
[[ -n "${OPENAI_API_KEY:-}" ]] || { printf 'OPENAI_API_KEY no está en el entorno del proceso\n' >&2; exit 2; }
kubectl create namespace poc-secrets --dry-run=client -o yaml | kubectl apply -f - >/dev/null
# The key flows only through stdin to a Kubernetes Secret, never through a
# command argument, manifest file, image layer, or the actor environment.
printf '%s' "$OPENAI_API_KEY" |
  kubectl -n poc-secrets create secret generic openai-api-key --from-file=token=/dev/stdin --dry-run=client -o yaml |
  kubectl apply -f - >/dev/null
cat <<'EOF' | kubectl apply -f - >/dev/null
apiVersion: v1
kind: ConfigMap
metadata:
  name: k8s-credential-provider-namespace-policy
  namespace: ate-system
data:
  namespace-policy.yaml: |
    policies:
    - atespace: ate-demo-counter
      allowedNamespaces:
      - poc-secrets
EOF
kubectl -n ate-system rollout restart deployment/k8s-credential-provider >/dev/null
kubectl -n ate-system rollout status deployment/k8s-credential-provider --timeout=3m >/dev/null
printf 'Gateway local preparado para inyectar la credencial de OpenAI\n'

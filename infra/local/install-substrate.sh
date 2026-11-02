#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
require_command go
require_command kubectl
require_upstream
export ATE_INSTALL_KIND=true
(cd "$UPSTREAM_DIR" && go run ./cmd/ate-setup deploy ate-system \
  --sandbox-classes=gvisor \
  --rollout-timeout=5m \
  --credential-provider='{"name":"k8s.io"}' \
  --ingress-allowed-spiffe-ids=spiffe://cluster.local/ns/ate-system/sa/atenet-client)
(cd "$UPSTREAM_DIR" && go run ./cmd/ate-setup deploy demo counter)
(cd "$UPSTREAM_DIR" && go build -o "$ROOT/infra/.cache/kubectl-ate" ./cmd/kubectl-ate)
kubectl -n ate-system get pods
kubectl -n ate-system wait --for=condition=Ready pod --all --field-selector=status.phase!=Succeeded --timeout=300s
printf 'Substrate y demo counter listos\n'

#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
command -v kubectl >/dev/null || exit 2
resources="$(kubectl api-resources --api-group=certificates.k8s.io -o name)"
printf '%s\n' "$resources" | grep -Eq '^podcertificaterequests(\.certificates\.k8s\.io)?$'
printf '%s\n' "$resources" | grep -Eq '^clustertrustbundles(\.certificates\.k8s\.io)?$'
kubectl apply -f "$root/infra/k8s/smoke/pod-certificate.yaml" >/dev/null
trap 'kubectl -n ate-system delete pod poc-pod-certificate-smoke --ignore-not-found --wait=false >/dev/null 2>&1 || true' EXIT
kubectl -n ate-system wait --for=condition=Ready pod/poc-pod-certificate-smoke --timeout=180s || {
  kubectl -n ate-system describe pod poc-pod-certificate-smoke >&2
  exit 1
}
printf 'PASS: API PodCertificateRequest/ClusterTrustBundle y montaje de certificado\n'

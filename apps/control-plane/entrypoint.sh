#!/bin/sh
set -eu
sa_dir=/var/run/secrets/kubernetes.io/serviceaccount
: "${KUBERNETES_SERVICE_HOST:?Kubernetes API host missing}"
: "${KUBERNETES_SERVICE_PORT:?Kubernetes API port missing}"
test -r "$sa_dir/token"
test -r "$sa_dir/ca.crt"
config=/tmp/poc-kubeconfig
cat > "$config" <<EOF
apiVersion: v1
kind: Config
clusters:
- name: incluster
  cluster:
    server: https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT}
    certificate-authority: $sa_dir/ca.crt
contexts:
- name: incluster
  context:
    cluster: incluster
    user: poc
current-context: incluster
users:
- name: poc
  user:
    tokenFile: $sa_dir/token
EOF
chmod 600 "$config"
export KUBECONFIG="$config"
exec node /app/dist/server.js

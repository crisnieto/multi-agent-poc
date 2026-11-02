#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
source_dir="$root/infra/.cache/substrate"
eks_dir="$root/infra/.cache/substrate-eks"
commit="$(sed -n 's/^commit=//p' "$root/infra/substrate.lock")"
region="${POC_AWS_REGION:-}"
[[ "$region" =~ ^[a-z]{2}-[a-z]+-[0-9]+$ ]] || {
  printf 'Configurar POC_AWS_REGION para el overlay EKS\n' >&2; exit 2;
}
[[ -d "$source_dir/.git" && "$(git -C "$source_dir" rev-parse HEAD)" == "$commit" ]] || {
  printf 'Falta el checkout Substrate del commit fijado; ejecutar infra/local/up.sh primero\n' >&2; exit 2;
}
git -C "$source_dir" diff --quiet && git -C "$source_dir" diff --cached --quiet || {
  printf 'El checkout Substrate original tiene cambios locales\n' >&2; exit 2;
}
if [[ ! -d "$eks_dir" ]]; then
  git -C "$source_dir" worktree add --quiet --detach "$eks_dir" "$commit"
fi
[[ "$(git -C "$eks_dir" rev-parse HEAD)" == "$commit" ]] || {
  printf 'El worktree EKS no coincide con substrate.lock\n' >&2; exit 2;
}

POC_EKS_WORKTREE="$eks_dir" POC_AWS_REGION="$region" python3 - <<'PY'
from pathlib import Path
import os

root = Path(os.environ['POC_EKS_WORKTREE']) / 'manifests' / 'ate-install'
region = os.environ['POC_AWS_REGION']
for name in ('atelet.yaml', 'ate-api-server.yaml'):
    path = root / name
    content = path.read_text()
    old = '        - name: ATE_STORAGE_BACKEND\n          value: "gcs"'
    new = f'        - name: ATE_STORAGE_BACKEND\n          value: "s3"\n        - name: AWS_REGION\n          value: "{region}"'
    if content.count(old) == 1:
        content = content.replace(old, new, 1)
    elif content.count(new) != 1:
        raise SystemExit(f'{name}: valor de storage inesperado; revisar upstream')
    if name == 'atelet.yaml':
        replacements = {
            '          path: /home/kubernetes/bin\n': '          path: /etc/eks/image-credential-provider\n',
            '          path: /etc/srv/kubernetes/cri_auth_config.yaml\n': '          path: /etc/eks/image-credential-provider/config.json\n',
        }
        for before, after in replacements.items():
            if content.count(before) == 1:
                content = content.replace(before, after, 1)
            elif content.count(after) != 1:
                raise SystemExit(f'atelet.yaml: ruta de credenciales inesperada: {before}')
    path.write_text(content)

# PodMonitoring es exclusivo de Google Managed Prometheus y EKS no trae su CRD.
base = root / 'base' / 'kustomization.yaml'
content = base.read_text()
gke_monitor = '  - ../atenet-router-monitoring.yaml\n'
if content.count(gke_monitor) == 1:
    base.write_text(content.replace(gke_monitor, '', 1))
elif 'atenet-router-monitoring.yaml' in content:
    raise SystemExit('base/kustomization.yaml: referencia PodMonitoring inesperada')
print('Overlay EKS preparado en infra/.cache/substrate-eks (ignorado por Git)')
PY

# El instalador upstream exige una cuenta de transferencia GCS para cualquier
# clúster que no sea kind, aun cuando snapshot-location selecciona S3.
POC_EKS_WORKTREE="$eks_dir" python3 - <<'PY'
from pathlib import Path
import os

path = Path(os.environ['POC_EKS_WORKTREE']) / 'cmd/ate-setup/internal/config/config.go'
content = path.read_text()
old = '''// ate-setup installs GCS everywhere but kind, which uses S3.
func (c *Config) RequireTransferServiceAccount() error {
\tif c.Kind {
\t\treturn nil
\t}'''
new = '''// An S3 snapshot location does not need a GCS transfer service account.
func (c *Config) RequireTransferServiceAccount() error {
\tif c.Kind || strings.HasPrefix(c.SnapshotLocation, "s3://") {
\t\treturn nil
\t}'''
if content.count(old) == 1:
    path.write_text(content.replace(old, new, 1))
elif content.count(new) != 1:
    raise SystemExit('config.go: validación de GCS inesperada; revisar upstream')

test = Path(os.environ['POC_EKS_WORKTREE']) / 'cmd/ate-setup/internal/config/poc_s3_overlay_test.go'
test.write_text('''package config

import "testing"

func TestPoCS3DoesNotRequireGCSAccount(t *testing.T) {
    c := &Config{SnapshotLocation: "s3://poc-snapshots/"}
    if err := c.RequireTransferServiceAccount(); err != nil {
        t.Fatalf("S3 must not require a GCS account: %v", err)
    }
}

func TestPoCGCSStillRequiresTransferAccount(t *testing.T) {
    c := &Config{SnapshotLocation: "gs://poc-snapshots/"}
    if err := c.RequireTransferServiceAccount(); err == nil {
        t.Fatal("GCS must require a transfer account")
    }
}
''')
PY

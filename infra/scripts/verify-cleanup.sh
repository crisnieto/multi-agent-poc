#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
"$root/infra/scripts/audit-residuals.sh"

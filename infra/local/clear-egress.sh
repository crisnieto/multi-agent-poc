#!/usr/bin/env bash
set -euo pipefail
kubectl -n poc-secrets delete secret openai-api-key --ignore-not-found >/dev/null
printf 'Se eliminó el secreto OpenAI del clúster local\n'

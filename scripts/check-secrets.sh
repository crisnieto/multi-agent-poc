#!/usr/bin/env bash
set -euo pipefail

# Defense in depth for accidentally staged or pushed OpenAI API keys.
# The key must be provided only at runtime; this scanner never prints a match.
pattern='sk-[A-Za-z0-9_-]{20,}'

is_secret_path() {
  local path="$1"
  case "$path" in
    */example.env|*.env.example|*.tfvars.example) return 1 ;;
    .env|.env.*|*.env|*.tfvars|*.credentials.json|auth.json|*/auth.json|*.secret.yaml|*.secret.yml|*/secrets/*) return 0 ;;
  esac
  return 1
}

case "${1:-}" in
  staged)
    while IFS= read -r -d '' path; do
      if is_secret_path "$path"; then
        printf 'Secret file cannot be committed: %s\n' "$path" >&2
        exit 1
      fi
      if git show ":$path" | LC_ALL=C grep -Ea "$pattern" >/dev/null; then
        printf 'Potential OpenAI key found in staged file: %s\n' "$path" >&2
        exit 1
      fi
    done < <(git diff --cached --name-only -z --diff-filter=ACMR)
    ;;
  push)
    while read -r local_ref local_sha remote_ref remote_sha; do
      [[ -n "${local_sha:-}" ]] || continue
      [[ "$local_sha" =~ ^0+$ ]] && continue
      if [[ "${remote_sha:-}" =~ ^0+$ ]]; then
        commits=$(git rev-list "$local_sha" --not --remotes)
      else
        commits=$(git rev-list "${remote_sha}..${local_sha}")
      fi
      while IFS= read -r commit; do
        [[ -n "$commit" ]] || continue
        if git grep -I -q -E "$pattern" "$commit"; then
          printf 'Potential OpenAI key found in outgoing commit %s\n' "$commit" >&2
          exit 1
        fi
        while IFS= read -r path; do
          if is_secret_path "$path"; then
            printf 'Secret file found in outgoing commit %s: %s\n' "$commit" "$path" >&2
            exit 1
          fi
        done < <(git ls-tree -r --name-only "$commit")
      done <<< "$commits"
    done
    ;;
  *)
    printf 'Usage: %s staged|push\n' "$0" >&2
    exit 2
    ;;
esac

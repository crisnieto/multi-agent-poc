#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
runtime="$root/infra/.runtime"
deadline_file="$runtime/stop-deadline-utc"
pid_file="$runtime/stop-timer.pid"
action="${1:-status}"
case "$action" in
  arm|arm-until)
    if [[ "$action" == arm ]]; then
      hours="${2:-}"
      [[ "$hours" =~ ^[0-9]+$ ]] && (( hours > 0 && hours <= 72 )) || { printf 'Indicar entre 1 y 72 horas enteras\n' >&2; exit 2; }
      deadline="$(node -e 'console.log(new Date(Date.now()+Number(process.argv[1])*3600000).toISOString())' "$hours")"
    else
      deadline="${2:-}"
      node -e 'const d=Date.parse(process.argv[1]),n=Date.now();if(!Number.isFinite(d)||d<=n||d-n>72*3600000)process.exit(1)' "$deadline" || {
        printf 'Indicar una fecha UTC futura dentro de 72 horas\n' >&2; exit 2;
      }
    fi
    [[ -n "${POC_TFVARS:-}" && -f "$POC_TFVARS" && -n "${POC_AWS_REGION:-}" ]] || { printf 'Configurar POC_TFVARS y POC_AWS_REGION antes de armar\n' >&2; exit 2; }
    if [[ -f "$pid_file" ]] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then printf 'Ya hay un temporizador activo\n' >&2; exit 2; fi
    mkdir -p "$runtime"
    printf '%s\n' "$deadline" >"$deadline_file"
    POC_TFVARS="$POC_TFVARS" POC_AWS_REGION="$POC_AWS_REGION" POC_PROJECT_NAME="${POC_PROJECT_NAME:-substrate-poc}" nohup "$0" run >>"$runtime/stop-timer.log" 2>&1 </dev/null &
    printf '%s\n' "$!" >"$pid_file"
    printf 'Apagado programado para %s UTC (PID %s)\n' "$deadline" "$(cat "$pid_file")"
    ;;
  run)
    [[ -f "$deadline_file" ]] || exit 2
    deadline="$(cat "$deadline_file")"
    while :; do
      remaining="$(node -e 'const n=Date.parse(process.argv[1]); if(!Number.isFinite(n)) process.exit(2); console.log(Math.max(0,Math.ceil((n-Date.now())/1000)))' "$deadline")"
      (( remaining > 0 )) || break
      sleep "$(( remaining > 30 ? 30 : remaining ))"
    done
    printf 'Hora de cierre alcanzada: %s\n' "$deadline"
    for attempt in {1..10}; do
      if "$root/infra/scripts/destroy.sh"; then
        rm -f "$pid_file" "$deadline_file"
        exit 0
      fi
      printf 'Intento de limpieza %s falló; reintentando en 30 s\n' "$attempt" >&2
      sleep 30
    done
    printf 'La limpieza automática falló; ejecutar destroy.sh de inmediato\n' >&2
    exit 1
    ;;
  disarm)
    if [[ -f "$pid_file" ]]; then
      pid="$(cat "$pid_file")"
      kill "$pid" 2>/dev/null || true
    fi
    rm -f "$pid_file" "$deadline_file"
    ;;
  status)
    [[ -f "$deadline_file" && -f "$pid_file" ]] || { printf 'Temporizador no armado\n'; exit 1; }
    pid="$(cat "$pid_file")"
    kill -0 "$pid" 2>/dev/null || { printf 'Temporizador detenido antes del apagado; ejecutar destroy.sh\n' >&2; exit 1; }
    printf 'Temporizador activo hasta %s (PID %s)\n' "$(cat "$deadline_file")" "$pid"
    ;;
  *) printf 'Uso: stop-timer.sh arm HORAS | arm-until UTC_ISO | status | disarm\n' >&2; exit 2;;
esac

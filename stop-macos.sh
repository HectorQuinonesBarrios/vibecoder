#!/usr/bin/env bash
set -euo pipefail

state_dir="$HOME/Library/Application Support/Odysseus"
install_dir="${ODYSSEUS_HOME:-$HOME/odysseus}"
odysseus_port="${ODYSSEUS_PORT:-${APP_PORT:-7860}}"

if [[ -f "$install_dir/.env" && -z "${ODYSSEUS_PORT:-${APP_PORT:-}}" ]]; then
  configured_port="$(awk -F= '$1 == "APP_PORT" { gsub(/[[:space:]#].*/, "", $2); print $2; exit }' "$install_dir/.env")"
  [[ "$configured_port" =~ ^[0-9]+$ ]] && odysseus_port="$configured_port"
fi

stop_tree() {
  local pid="$1"
  local child
  while IFS= read -r child; do
    [[ -n "$child" ]] && stop_tree "$child"
  done < <(pgrep -P "$pid" 2>/dev/null || true)
  kill -TERM "$pid" 2>/dev/null || true
}

stop_managed() {
  local service="$1"
  local pid_file="$state_dir/$service.pid"
  local expected="$2"
  local pid command

  if [[ ! -f "$pid_file" ]]; then
    printf '%s was not started by this launcher. Leaving it alone.\n' "$service"
    return
  fi

  pid="$(<"$pid_file")"
  if [[ ! "$pid" =~ ^[0-9]+$ ]] || ! kill -0 "$pid" 2>/dev/null; then
    rm -f "$pid_file"
    printf 'Removed stale %s process record.\n' "$service"
    return
  fi

  command="$(ps -p "$pid" -o command= 2>/dev/null || true)"
  if [[ "$command" != *"$expected"* ]]; then
    printf 'PID %s no longer matches the recorded %s process; not stopping it.\n' "$pid" "$service" >&2
    rm -f "$pid_file"
    return
  fi

  printf 'Stopping %s (PID %s)...\n' "$service" "$pid"
  stop_tree "$pid"
  rm -f "$pid_file"
}

stop_legacy_odysseus() {
  local install_path pid command cwd
  [[ -d "$install_dir" ]] || return
  install_path="$(cd "$install_dir" && pwd -P)"
  pid="$(lsof -tiTCP:"$odysseus_port" -sTCP:LISTEN 2>/dev/null | head -n 1 || true)"
  [[ "$pid" =~ ^[0-9]+$ ]] || return

  command="$(ps -p "$pid" -o command= 2>/dev/null || true)"
  cwd="$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -n 1)"
  if [[ "$command" == *'uvicorn app:app'* && "$cwd" == "$install_path" ]]; then
    printf 'Found Odysseus from a legacy start (PID %s, port %s); stopping it.\n' "$pid" "$odysseus_port"
    stop_tree "$pid"
  else
    printf 'Found a listener on Odysseus port %s, but could not verify it belongs to %s; leaving it alone.\n' "$odysseus_port" "$install_path" >&2
  fi
}

stop_legacy_ollama() {
  local pid command answer
  pid="$(lsof -tiTCP:11434 -sTCP:LISTEN 2>/dev/null | head -n 1 || true)"
  [[ "$pid" =~ ^[0-9]+$ ]] || return
  command="$(ps -p "$pid" -o command= 2>/dev/null || true)"
  [[ "$command" == *'ollama serve'* ]] || return

  printf 'Found an untracked Ollama server (PID %s): %s\n' "$pid" "$command"
  read -r -p 'Stop this Ollama server too? [y/N] ' answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    stop_tree "$pid"
  else
    printf 'Leaving Ollama running.\n'
  fi
}

if [[ -f "$state_dir/odysseus.pid" ]]; then
  stop_managed odysseus "$install_dir/start-macos.sh"
else
  stop_legacy_odysseus
fi

if [[ -f "$state_dir/ollama.pid" ]]; then
  stop_managed ollama 'ollama serve'
else
  stop_legacy_ollama
fi

printf 'Stop request complete. Unverified or separately managed services were left running.\n'

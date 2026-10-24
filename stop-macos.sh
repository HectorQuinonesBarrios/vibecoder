#!/usr/bin/env bash
set -euo pipefail

state_dir="$HOME/Library/Application Support/Odysseus"
install_dir="${ODYSSEUS_HOME:-$HOME/odysseus}"

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

stop_managed odysseus "$install_dir/start-macos.sh"
stop_managed ollama 'ollama serve'
printf 'Stop request complete. Any service not launched by this starter script was left running.\n'

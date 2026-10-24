#!/usr/bin/env bash
set -euo pipefail

install_dir="${ODYSSEUS_HOME:-$HOME/odysseus}"
ollama_url="http://127.0.0.1:11434/api/tags"
odysseus_url="http://127.0.0.1:7860"
log_dir="$HOME/Library/Logs/odysseus"
state_dir="$HOME/Library/Application Support/Odysseus"

if [[ ! -x "$install_dir/start-macos.sh" ]]; then
  printf 'Odysseus was not found at %s. Run setup-macos.sh first.\n' "$install_dir" >&2
  exit 1
fi

if ! command -v ollama >/dev/null 2>&1; then
  printf 'Ollama was not found. Install it from https://ollama.com/download, then run this script again.\n' >&2
  exit 1
fi

mkdir -p "$log_dir" "$state_dir"

if ! curl -fsS "$ollama_url" >/dev/null 2>&1; then
  printf 'Starting Ollama...\n'
  nohup ollama serve >"$log_dir/ollama.log" 2>&1 </dev/null &
  ollama_pid=$!
  printf '%s\n' "$ollama_pid" >"$state_dir/ollama.pid"
  for attempt in {1..45}; do
    if curl -fsS "$ollama_url" >/dev/null 2>&1; then
      break
    fi
    if [[ "$attempt" -eq 45 ]]; then
      printf 'Ollama did not start. Check %s/ollama.log\n' "$log_dir" >&2
      exit 1
    fi
    sleep 1
  done
else
  printf 'Ollama is already online.\n'
fi

if ! ollama list | awk 'NR > 1 && NF { found=1 } END { exit !found }'; then
  read -r -p 'No Ollama models are installed. Download qwen2.5-coder:3b (~2 GB)? [Y/n] ' answer
  if [[ ! "$answer" =~ ^[Nn]$ ]]; then
    ollama pull qwen2.5-coder:3b
  else
    printf 'No model is installed; Odysseus can start, but chat will not work until you add a model.\n'
  fi
fi

if ! curl -fsS "$odysseus_url" >/dev/null 2>&1; then
  printf 'Starting Odysseus...\n'
  nohup "$install_dir/start-macos.sh" >"$log_dir/odysseus.log" 2>&1 </dev/null &
  odysseus_pid=$!
  printf '%s\n' "$odysseus_pid" >"$state_dir/odysseus.pid"
  for attempt in {1..90}; do
    if curl -fsS "$odysseus_url" >/dev/null 2>&1; then
      break
    fi
    if [[ "$attempt" -eq 90 ]]; then
      printf 'Odysseus did not start. Check %s/odysseus.log\n' "$log_dir" >&2
      exit 1
    fi
    sleep 1
  done
else
  printf 'Odysseus is already online.\n'
fi

printf 'Ollama and Odysseus are ready. Opening %s\n' "$odysseus_url"
printf 'If Odysseus still reports no model, add/select the Ollama provider at http://localhost:11434/v1 in Settings.\n'
open "$odysseus_url"
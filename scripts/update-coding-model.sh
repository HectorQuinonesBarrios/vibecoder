#!/usr/bin/env bash
set -euo pipefail

model="${1:-${ODYSSEUS_CODING_MODEL:-qwen2.5-coder:3b}}"
if [[ ! "$model" =~ ^[A-Za-z0-9._:/-]+$ ]]; then
  printf 'Invalid Ollama model tag: %s\n' "$model" >&2
  exit 2
fi

if ! command -v ollama >/dev/null 2>&1; then
  printf 'Ollama is not installed. Install it from https://ollama.com/download first.\n' >&2
  exit 1
fi

if ! curl -fsS http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
  printf 'Ollama is not running. Open the Ollama app, then rerun this script.\n' >&2
  exit 1
fi

printf 'Refreshing coding model %s from its current Ollama tag. This may download several gigabytes.\n' "$model"
ollama pull "$model"
printf 'Model %s is ready. Restart or reselect it in Odysseus if it was already loaded.\n' "$model"

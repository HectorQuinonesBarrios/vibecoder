#!/usr/bin/env bash
set -euo pipefail

repo_url="https://github.com/odysseus-dev/odysseus.git"
install_dir="${ODYSSEUS_HOME:-$HOME/odysseus}"

if ! command -v git >/dev/null 2>&1; then
  printf 'Git is required. Install it, then run this script again.\n'
  exit 1
fi

if [[ ! -d "$install_dir/.git" ]]; then
  if [[ -e "$install_dir" ]]; then
    printf 'Install path already exists and is not an Odysseus Git checkout: %s\n' "$install_dir" >&2
    exit 1
  fi
  printf 'Cloning the stable main branch into %s\n' "$install_dir"
  git clone --branch main --single-branch "$repo_url" "$install_dir"
else
  printf 'Using existing checkout at %s (not changing its branch or local files).\n' "$install_dir"
  remote_url="$(git -C "$install_dir" remote get-url origin)"
  if [[ "$remote_url" != "$repo_url" && "$remote_url" != "https://github.com/odysseus-dev/odysseus" ]]; then
    printf 'The existing checkout origin is not the official Odysseus repository: %s\n' "$remote_url" >&2
    exit 1
  fi
fi

if command -v ollama >/dev/null 2>&1; then
  printf '\nChoose a coding model to download (requires free disk space):\n'
  printf '  1) qwen2.5-coder:3b  (small, suitable for limited memory)\n'
  printf '  2) qwen2.5-coder:7b  (better coding, 16 GB system memory recommended)\n'
  printf '  3) qwen2.5-coder:14b (stronger, 32 GB system memory recommended)\n'
  read -r -p 'Model [1/2/3, default 1]: ' model_choice
  case "${model_choice:-1}" in
    1) model="qwen2.5-coder:3b" ;;
    2) model="qwen2.5-coder:7b" ;;
    3) model="qwen2.5-coder:14b" ;;
    *) printf 'Invalid model choice.\n' >&2; exit 2 ;;
  esac
  ollama pull "$model"
else
  printf '\nOllama is not installed or not on PATH. Install it from https://ollama.com/download, then run:\n'
  printf '  ollama pull qwen2.5-coder:3b\n'
fi

printf '\nStarting Odysseus. Keep this Terminal window open while it runs.\n'
cd "$install_dir"
exec ./start-macos.sh
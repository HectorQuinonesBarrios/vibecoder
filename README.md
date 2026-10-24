# Odysseus Local Coding Agent Starter

This starter automates a native Odysseus install and can download a local coding model through Ollama. Odysseus is the agent workspace; Ollama runs the model. The app is free and open source. The scripts target macOS and Windows and use the official Odysseus GitHub repository's stable `main` branch.

## Before running

- Review the scripts before execution. They clone and run software from `https://github.com/odysseus-dev/odysseus` and install its Python dependencies.
- Install Git. On macOS, install Homebrew; Odysseus's native launcher uses it for dependencies. On Windows, install Git for Windows.
- For local model responses, install Ollama from [ollama.com/download](https://ollama.com/download). The scripts continue without Ollama, but no model will be downloaded.
- A local model needs RAM and disk space. Start with the 3B option on a modest computer; 7B is a better coding starting point with about 16 GB system memory; 14B is intended for systems with about 32 GB. These are practical estimates, not guarantees.

## Install and run

### macOS

In Terminal, from this folder:

```sh
chmod +x setup-macos.sh
./setup-macos.sh
```

After the server starts, open `http://127.0.0.1:7860` in your browser. Native setup is recommended on Apple Silicon for Metal acceleration; Docker on macOS does not expose the Apple GPU to local model serving.

### Windows

Open PowerShell in this folder and run:

```powershell
powershell -ExecutionPolicy Bypass -File .\setup-windows.ps1
```

After the server starts, open `http://127.0.0.1:7000` in your browser. Upstream notes that Windows is not actively tested, so expect occasional rough edges. If PowerShell blocks the script, review the file and run it from a normal user account; do not disable machine-wide execution policy.

Both scripts use `~/odysseus` by default. To choose another install directory, set `ODYSSEUS_HOME` before running the script. Existing checkouts are not updated automatically.

## Connect the model

In Odysseus, open Settings and add the Ollama provider using the OpenAI-compatible endpoint:

```text
http://localhost:11434/v1
```

Select the model downloaded by the setup script, such as `qwen2.5-coder:3b`. Keep Ollama running while using Odysseus. If you install Ollama after the first run, download a model with `ollama pull qwen2.5-coder:3b`.

The exact Settings labels can vary by Odysseus version. Do not use the Docker host endpoint unless Odysseus itself is running in Docker.

## Enable coding-agent tools

Odysseus's agent is a workspace with a model backend, not an extension that automatically attaches to a VS Code window. To use it for a codebase:

1. In Odysseus, open the agent/chat settings and enable its file read/write and shell tools for the admin account. These tools are admin-only in Odysseus.
2. Select or open only the project folder you intend the agent to work in, where the current Odysseus version permits it.
3. Import [`skills/coding-agent/SKILL.md`](skills/coding-agent/SKILL.md) as a skill and enable it for coding sessions.
4. Ask the agent to inspect the project first. Review each proposed file path and shell command, and approve actions one at a time.

Odysseus's shell and file tools are **not sandboxed**; they run with the permissions of the user running Odysseus. Do not expose the app publicly, disable authentication, or blanket-approve tools. Keep it bound to localhost for initial use. Do not add email, calendar, MCP, or network tools unless you specifically need them. A local model keeps prompts on-device, but using web search, cloud providers, external MCP servers, or network access can send data elsewhere.

For inline completions and direct VS Code workflow, Odysseus alone is not enough; pair the local Ollama model with a VS Code extension that supports Ollama, such as Continue.

## Official references

- [Odysseus source and releases](https://github.com/odysseus-dev/odysseus)
- [Windows setup notes](https://odysseusai.dev/windows)
- [macOS setup notes](https://odysseusai.dev/install/macos)
- [Model providers](https://odysseusai.dev/providers)
- [Agent security notes](https://odysseusai.dev/agent-security)
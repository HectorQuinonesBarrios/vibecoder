# Odysseus Local Coding Agent Starter

This starter automates a native Odysseus install and can download a local coding model through Ollama. Odysseus is the agent workspace; Ollama runs the model. The app is free and open source. The scripts target macOS and Windows and use the official Odysseus GitHub repository's stable `main` branch.

## Before running

- Review the scripts before execution. They clone and run software from `https://github.com/odysseus-dev/odysseus` and install its Python dependencies.
- Install Git. On macOS, install Homebrew; Odysseus's native launcher uses it for dependencies. On Windows, install Git for Windows.
- For local model responses, install and open Ollama from [ollama.com/download](https://ollama.com/download) before running the setup script. The script downloads your selected model only when Ollama is installed and running.
- Recommended starting model: `qwen2.5-coder:3b` (about 2 GB download, suitable starting point for 8 GB RAM). Choose `qwen2.5-coder:7b` (about 5 GB; 16 GB RAM recommended) for stronger coding, or `qwen2.5-coder:14b` (about 9 GB; 32 GB RAM recommended). Actual memory needs depend on context length and other apps.

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

## Start both services

After setup, use the startup script whenever Odysseus says Ollama is offline. It checks Ollama first, starts its local server if needed, then starts Odysseus and opens the browser. If Ollama has no models, it offers to download `qwen2.5-coder:3b`.

macOS:

```sh
./start-macos.sh
```

Windows PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\start-windows.ps1
```

The scripts assume the native install directory `~/odysseus` (or `ODYSSEUS_HOME` if customized). Keep authentication enabled and use these scripts only for localhost access unless you separately configure a secure private network route.

To stop the services that these scripts started:

macOS:

```sh
./stop-macos.sh
```

Windows PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\stop-windows.ps1
```

The stop scripts use recorded process IDs and verify the process before stopping it. They leave Ollama or Odysseus running if it was already running before the startup script.

## Connect the model

Downloading a model into Ollama does not automatically register it in Odysseus. This separate provider step is why Odysseus may say that no model is available. In Odysseus, open Settings, add an Ollama/OpenAI-compatible provider, and enter:

```text
http://localhost:11434/v1
```

Select the model downloaded by the setup script, such as `qwen2.5-coder:3b`. Keep Ollama running while using Odysseus. If you install Ollama after the first run, open its app and run `ollama pull qwen2.5-coder:3b`, then add the provider above. The setup scripts now print these provider values after a successful model download.

The exact Settings labels can vary by Odysseus version. Do not use the Docker host endpoint unless Odysseus itself is running in Docker.

## Use Odysseus as a coding agent

Odysseus can use its Agent mode plus file and shell tools to inspect and change a project. It is not an editor plugin that attaches to a VS Code window; you work in Odysseus chat and review the resulting changes in your normal editor. For each coding task:

1. Import [`skills/coding-agent/SKILL.md`](skills/coding-agent/SKILL.md) through Odysseus Skills and enable it for the coding chat. Review the skill before importing it; skills are instructions supplied to the model.
2. Start an Agent-mode chat and name the exact project directory in your first request. This lets Odysseus bind file and shell operations to the intended workspace. For example:

	```text
	Please work as my coding agent in /absolute/path/to/my-project. Inspect the project, then implement [describe the change]. Run the relevant tests and summarize the files changed and results. Ask before installing packages or doing anything outside this project.
	```

	On Windows, use the full project path, for example `C:\Users\YourName\source\my-project`. If Odysseus shows a workspace selector, choose the same project there too.

3. If the agent cannot inspect or edit files, sign in with an admin account and check that Agent use and shell/file permissions are enabled in Odysseus user privileges and that those tools are not globally disabled. The tool approvals should remain enabled; review each exact file path or command before approving it.
4. Check the diff in your editor and run or review the reported tests before accepting the work.

Odysseus's shell and file tools are **not sandboxed**; they run with the permissions of the user running Odysseus. Workspace selection helps keep the task scoped, but it is not an operating-system security boundary. Keep Odysseus on localhost, keep authentication enabled, and do not blanket-approve tools. Do not enable email, calendar, MCP, or web tools for coding unless needed. A local model keeps model prompts on-device, but using cloud providers, web search, or external MCP servers can send data elsewhere.

For inline completions and direct VS Code workflow, pair the local Ollama model with a VS Code extension such as Continue. Continue provides the editor integration; Odysseus provides its own browser-based agent workspace.

## Official references

- [Odysseus source and releases](https://github.com/odysseus-dev/odysseus)
- [Windows setup notes](https://odysseusai.dev/windows)
- [macOS setup notes](https://odysseusai.dev/install/macos)
- [Model providers](https://odysseusai.dev/providers)
- [Agent security notes](https://odysseusai.dev/agent-security)
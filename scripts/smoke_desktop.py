"""Start a desktop build with disposable data and check its first-run UI.

    python scripts/smoke_desktop.py
    python scripts/smoke_desktop.py --executable dist/windows/Odysseus/Odysseus.exe

No model/provider credentials are needed. No browser or tray is opened.
"""
import argparse
import json
import os
from pathlib import Path
import secrets
import socket
import subprocess
import sys
import tempfile
import time
from urllib.error import URLError
from urllib.request import ProxyHandler, Request, build_opener


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--executable", type=Path)
    parser.add_argument("--timeout", type=int, default=120)
    parser.add_argument("--ui", action="store_true", help="Also initialize the native tray/menu-bar UI")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    command = ([str(args.executable.resolve())] if args.executable else
               [sys.executable, str(root / "launcher.py")])
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
    opener = build_opener(ProxyHandler({}))
    base = f"http://127.0.0.1:{port}"

    def get(path):
        with opener.open(base + path, timeout=2) as response:
            assert response.status == 200, (path, response.status)
            return response.read()

    def post(path, payload):
        request = Request(base + path, data=json.dumps(payload).encode(),
                          headers={"Content-Type": "application/json"})
        with opener.open(request, timeout=10) as response:
            assert response.status == 200, (path, response.status)
            return json.loads(response.read())

    def wait_ready(process):
        deadline = time.monotonic() + args.timeout
        while True:
            if process.poll() is not None:
                raise RuntimeError(f"Desktop exited before startup: {process.returncode}")
            try:
                if json.loads(get("/api/health")).get("status") == "healthy":
                    return
            except (URLError, TimeoutError, OSError):
                pass
            if time.monotonic() >= deadline:
                raise TimeoutError("Desktop did not start before the deadline")
            time.sleep(0.25)

    def stop(process):
        if process.poll() is None:
            process.terminate()
        try:
            process.wait(timeout=15)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)

    with tempfile.TemporaryDirectory(prefix="odysseus-desktop-") as temporary:
        work = Path(temporary)
        env = os.environ.copy()
        env.update({
            "ODYSSEUS_DATA_DIR": str(work / "data"),
            "ODYSSEUS_CONFIG_DIR": str(work / "config"),
            "DATABASE_URL": f"sqlite:///{(work / 'data' / 'app.db').as_posix()}",
            "APP_BIND": "127.0.0.1", "APP_PORT": str(port),
            "ODYSSEUS_NO_OPEN": "1", "ODYSSEUS_TOOL_INDEX_PREWARM": "0",
            "ODYSSEUS_NO_BROWSER": "1",
            "AUTH_ENABLED": "true", "LOCALHOST_BYPASS": "false",
            "DEBUG": "false",
            "FASTEMBED_CACHE_PATH": str(work / "embedding-cache"),
            "HF_HOME": str(work / "huggingface"), "HF_HUB_OFFLINE": "1",
            # Never attach the disposable run to an existing local vector DB.
            "CHROMADB_HOST": "127.0.0.1", "CHROMADB_PORT": str(port),
        })
        if args.ui:
            env.pop("ODYSSEUS_NO_OPEN", None)
        # Preserve no real account or provider credentials in this smoke run.
        for key in list(env):
            if key.endswith("_API_KEY") or key in {"ODYSSEUS_ADMIN_USER", "ODYSSEUS_ADMIN_PASSWORD"}:
                env.pop(key)
        output = work / "process.log"
        with output.open("w", encoding="utf-8") as log:
            process = subprocess.Popen(command, cwd=work, env=env, stdout=log, stderr=log)
            try:
                wait_ready(process)
                assert b"<html" in get("/login").lower(), "Login page is missing"
                assert get("/static/app.js"), "Frontend bundle is missing"
                status = json.loads(get("/api/auth/status"))
                assert status.get("configured") is False, status
                assert (work / "data" / "app.db").is_file(), "Database is missing"
                credentials = {"username": "desktop-smoke", "password": secrets.token_urlsafe(24)}
                assert post("/api/auth/setup", credentials).get("ok") is True
                stop(process)
                process = subprocess.Popen(command, cwd=work, env=env, stdout=log, stderr=log)
                wait_ready(process)
                assert json.loads(get("/api/auth/status")).get("configured") is True
                assert post("/api/auth/login", credentials).get("ok") is True
                print("PASS: startup, frontend assets, first-run account, restart, persisted login")
            except Exception:
                for path in (output, work / "data" / "logs" / "launcher.log", work / "data" / "logs" / "app.log"):
                    if path.exists():
                        print(f"\n{path.name}:\n{path.read_text(encoding='utf-8', errors='replace')[-8000:]}", file=sys.stderr)
                raise
            finally:
                stop(process)


if __name__ == "__main__":
    main()

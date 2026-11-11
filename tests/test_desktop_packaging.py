"""Desktop packaging checks that do not require a frozen build."""
import os
import json
from pathlib import Path
import runpy
import shutil
import subprocess
import threading
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from unittest.mock import Mock

import pytest


ROOT = Path(__file__).resolve().parents[1]


def test_windows_spec_includes_runtime_assets():
    analysis = Mock()
    runpy.run_path(str(ROOT / "Odysseus.spec"), init_globals={
        "Analysis": analysis, "PYZ": Mock(), "EXE": Mock(), "COLLECT": Mock(),
    })
    options = analysis.call_args.kwargs
    sources = {source for source, _ in options["datas"]}
    assert {"resources", "HARNESS_VERSION", "static", "config", "LICENSE", "licenses"} <= sources
    for source in sources:
        assert (ROOT / source).exists(), f"Missing bundle input: {source}"
    assert {"services.search", "services.docs", "services.research", "services.memory", "services.shell"} <= set(options["hiddenimports"])


def test_windows_installer_is_per_user_and_model_refresh_is_explicit():
    installer = (ROOT / "installer/windows/Odysseus.iss").read_text(encoding="utf-8")
    build = (ROOT / "build-windows-portable.ps1").read_text(encoding="utf-8")
    updater = (ROOT / "scripts/update-coding-model.ps1").read_text(encoding="utf-8")

    assert "PrivilegesRequired=lowest" in installer
    assert "{localappdata}\\Programs\\Odysseus" in installer
    assert 'Source: "{#AppSourceDir}\\*"' in installer
    assert "update-coding-model.ps1" in installer
    assert "-ScheduleWeekly" in installer
    assert "-RemoveSchedule" in installer
    assert "ISCC.exe" in build
    assert '"/DInstallerSuffix=$suffix"' in build
    assert "& $ollama.Source pull $Model" in updater
    assert "Register-ScheduledTask" in updater
    assert "-DaysOfWeek Sunday" in updater
    assert "-LogonType Interactive" in updater
    assert "Unregister-ScheduledTask" in updater


def test_ios_pwa_install_docs_state_server_and_https_requirements():
    setup = (ROOT / "website/setup.md").read_text(encoding="utf-8").lower()
    manifest = json.loads((ROOT / "static/manifest.json").read_text(encoding="utf-8"))

    assert "add to home screen" in setup
    assert "safari" in setup
    assert "https" in setup
    assert "server" in setup and "iphone" in setup
    assert manifest["display"] == "standalone"


def test_macos_spec_creates_app_bundle_with_signing_identity(monkeypatch):
    monkeypatch.setattr(sys, "platform", "darwin")
    monkeypatch.setenv("ODYSSEUS_BUILD_MAC_APP", "1")
    identity = "Developer ID Application: Example (TEAM)"
    monkeypatch.setenv("ODYSSEUS_MAC_SIGN_IDENTITY", identity)
    bundle, executable = Mock(), Mock()
    runpy.run_path(str(ROOT / "Odysseus.spec"), init_globals={
        "Analysis": Mock(), "PYZ": Mock(), "EXE": executable, "COLLECT": Mock(), "BUNDLE": bundle,
    })
    assert executable.call_args.kwargs["codesign_identity"] == identity
    assert bundle.call_args.kwargs["name"] == "Odysseus.app"
    assert bundle.call_args.kwargs["info_plist"]["LSUIElement"] is True


@pytest.mark.parametrize("identity, profile", [
    (None, "notary-profile"), ("Apple Development: Example", None), ("-", None),
])
def test_release_signing_rejects_incomplete_or_development_credentials(identity, profile):
    from scripts.build_macos import validate_signing
    with pytest.raises(ValueError):
        validate_signing(identity, profile)


@pytest.mark.skipif(os.name == "nt", reason="macOS build interpreter uses Unix symlinks")
def test_signed_macos_build_staples_app_before_dmg(tmp_path, monkeypatch):
    from scripts import build_macos
    monkeypatch.setattr(build_macos, "ROOT", tmp_path)
    monkeypatch.setattr(sys, "platform", "darwin")
    monkeypatch.setattr(build_macos.platform, "machine", lambda: "arm64")
    # A venv executable is commonly a symlink; invoking the resolved target
    # would lose its installed packages.
    target = tmp_path / "base-python"
    target.touch()
    python = tmp_path / "venv-python"
    python.symlink_to(target)
    monkeypatch.chdir(tmp_path)
    monkeypatch.setattr(sys, "argv", ["build_macos.py", "--python", str(python), "--skip-install",
                                    "--sign-identity", "Developer ID Application: Example (TEAM)",
                                    "--notary-profile", "saved-profile"])
    monkeypatch.setattr(build_macos.subprocess, "check_output", lambda *a, **kw: "arm64\n")
    calls = []

    def run(*args, **kwargs):
        command = [str(arg) for arg in args]
        calls.append(command)
        if "PyInstaller" in command:
            (tmp_path / "dist/macos-arm64/Odysseus.app").mkdir(parents=True)
        if command[:2] == ["hdiutil", "create"]:
            Path(command[-1]).write_bytes(b"disk image fixture")
        return Mock(stdout='{"status":"Accepted"}')

    monkeypatch.setattr(build_macos, "run", run)
    build_macos.main()
    assert calls[0][0] == str(python)
    app_staple = next(i for i, cmd in enumerate(calls) if cmd[:3] == ["xcrun", "stapler", "staple"])
    image_create = next(i for i, cmd in enumerate(calls) if cmd[:2] == ["hdiutil", "create"])
    assert app_staple < image_create
    assert calls[-1][:3] == ["xcrun", "stapler", "validate"]
    assert list((tmp_path / "dist/macos-arm64").glob("*.sha256"))


def test_notarization_rejection_stops_release(monkeypatch):
    from scripts import build_macos
    monkeypatch.setattr(build_macos, "run", lambda *a, **kw: Mock(stdout='{"status":"Invalid","id":"submission-id"}'))
    with pytest.raises(RuntimeError, match="Notarization was not accepted: Invalid"):
        build_macos.notarize(Path("app.zip"), "saved-profile")


@pytest.mark.skipif(os.name == "nt" or not shutil.which("bash"), reason="macOS builder requires a Unix shell")
def test_macos_builder_preserves_special_characters_in_install_path(tmp_path):
    install = tmp_path / "Project with spaces & $money `literal` | quote's"
    install.mkdir()
    shutil.copy(ROOT / "build-macos-launcher.sh", install)
    (install / "licenses").mkdir()
    for name in ("THIRD_PARTY_PROVENANCE.json", "ACKNOWLEDGMENTS.md"):
        (install / name).write_text("fixture", encoding="utf-8")
    tools = tmp_path / "tools"
    tools.mkdir()
    # Packaging the disk image is separate from generating a valid launcher.
    hdiutil = tools / "hdiutil"
    hdiutil.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
    hdiutil.chmod(0o755)
    env = dict(os.environ, PATH=f"{tools}{os.pathsep}{os.environ['PATH']}", ODYSSEUS_PORT="7999")
    subprocess.run(["bash", str(install / "build-macos-launcher.sh")], env=env, check=True, capture_output=True)
    launcher = install / "dist/Odysseus.app/Contents/MacOS/Odysseus"
    subprocess.run(["bash", "-n", str(launcher)], check=True)
    assignments = "\n".join(launcher.read_text().splitlines()[:3])
    result = subprocess.run(["bash", "-c", assignments + '\nprintf "%s\\n%s" "$INSTALL_DIR" "$PORT"'],
                            check=True, capture_output=True, text=True)
    assert result.stdout == f"{install}\n7999"


@pytest.mark.skipif(not Path("/usr/bin/curl").exists() or not shutil.which("bash"), reason="macOS shell health probe")
@pytest.mark.parametrize("status, body, ready", [
    (200, b'{"status": "healthy"}', True),
    (503, b'{"status": "healthy"}', False),
    (200, b"a different application", False),
])
def test_macos_health_probe_requires_successful_app_response(status, body, ready):
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            assert self.path == "/api/health"
            self.send_response(status)
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *_args):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        source = (ROOT / "build-macos-launcher.sh").read_text()
        function = source[source.index("is_ready() {"):].split("\n}", 1)[0] + "\n}"
        result = subprocess.run(["bash", "-c", function + "\nis_ready"],
                                env=dict(os.environ, URL=f"http://127.0.0.1:{server.server_port}"))
        assert (result.returncode == 0) is ready
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)

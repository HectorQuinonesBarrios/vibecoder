# tests/test_launcher.py
import sys
import os
from pathlib import Path
from unittest import mock
import pytest

import launcher
from launcher import NullWriter, create_tray_image, on_open_browser, on_exit, open_browser


def test_frozen_multiprocessing_bootstrap_precedes_gui_and_app_imports():
    source = Path("launcher.py").read_text(encoding="utf-8")

    freeze = source.index("multiprocessing.freeze_support()")
    splash = source.index("if getattr(sys, 'frozen', False) and not os.getenv")
    app_import = source.index("from app import app")
    assert freeze < splash < app_import


def test_null_writer():
    writer = NullWriter()
    # writing and flushing should not raise any exceptions
    writer.write("hello")
    writer.flush()
    assert writer.isatty() is False


def test_create_tray_image():
    try:
        from PIL import Image
        img = create_tray_image()
        assert isinstance(img, Image.Image)
        assert img.size == (64, 64)
    except ImportError:
        pytest.skip("Pillow/PIL not installed in test environment")


def test_on_open_browser():
    with mock.patch("webbrowser.open") as mock_open:
        icon_mock = mock.Mock()
        item_mock = mock.Mock()
        url = "http://127.0.0.1:7000"
        on_open_browser(icon_mock, item_mock, url)
        mock_open.assert_called_once_with(url)


def test_on_exit():
    server = mock.Mock(should_exit=False)
    with mock.patch("os._exit") as mock_exit:
        icon_mock = mock.Mock()
        item_mock = mock.Mock()
        with mock.patch("launcher.active_server", server), mock.patch("launcher.shutdown_requested"):
            on_exit(icon_mock, item_mock)
        assert server.should_exit is True
        icon_mock.stop.assert_called_once()
        mock_exit.assert_not_called()


def test_open_browser():
    server = mock.Mock(started=True, should_exit=False)
    with mock.patch("webbrowser.open") as mock_open, \
         mock.patch("time.sleep") as mock_sleep:

        # Test when splash_root is None
        with mock.patch("launcher.splash_root", None):
            open_browser("http://127.0.0.1:7000", server)
            mock_open.assert_called_once_with("http://127.0.0.1:7000")
            mock_sleep.assert_not_called()

    with mock.patch("webbrowser.open") as mock_open, \
         mock.patch("time.sleep") as mock_sleep:
        # Test when splash_root is present and gets destroyed
        mock_splash = mock.Mock()
        with mock.patch("launcher.splash_root", mock_splash):
            open_browser("http://127.0.0.1:7000", server)
            mock_splash.after.assert_called_once()


def test_browser_waits_for_slow_startup():
    server = mock.Mock(started=False, should_exit=False)
    attempts = 0

    def startup_tick(_delay):
        nonlocal attempts
        mock_open.assert_not_called()
        attempts += 1
        if attempts == 50:
            server.started = True

    with mock.patch("launcher.webbrowser.open") as mock_open, \
         mock.patch("launcher.time.sleep", side_effect=startup_tick), \
         mock.patch("launcher.splash_root", None):
        open_browser("http://127.0.0.1:7011", server)
        assert attempts == 50
        mock_open.assert_called_once_with("http://127.0.0.1:7011")


@pytest.mark.parametrize("started", [False, True])
def test_browser_does_not_open_when_server_is_stopping(started):
    server = mock.Mock(started=started, should_exit=True)
    with mock.patch("launcher.webbrowser.open") as mock_open, \
         mock.patch("launcher.time.sleep") as mock_sleep:
        open_browser("http://127.0.0.1:7011", server)
        mock_open.assert_not_called()
        mock_sleep.assert_not_called()


@pytest.mark.parametrize("host, expected", [
    ("127.0.0.1", "127.0.0.1"), ("0.0.0.0", "127.0.0.1"),
    ("::", "[::1]"), ("::1", "[::1]"), ("[::1]", "[::1]"),
])
def test_browser_url(host, expected):
    assert launcher.browser_url(host, 7011) == f"http://{expected}:7011"


def test_frozen_runtime_uses_install_config_and_persistent_logs(tmp_path, monkeypatch):
    install = tmp_path / "App with spaces"
    install.mkdir()
    data = tmp_path / "User data"
    (install / ".env").write_text(
        f'\ufeffODYSSEUS_DATA_DIR="{data.as_posix()}"\nAPP_PORT=7999\n', encoding="utf-8"
    )
    elsewhere = tmp_path / "shortcut working directory"
    elsewhere.mkdir()
    (elsewhere / ".env").write_text("APP_PORT=8888\n", encoding="utf-8")
    with monkeypatch.context() as patch:
        patch.chdir(elsewhere)
        patch.setattr(sys, "executable", str(install / "Odysseus.exe"))
        patch.setattr(sys, "platform", "win32")
        patch.delenv("ODYSSEUS_DATA_DIR", raising=False)
        patch.setenv("APP_PORT", "7011")
        # Register restoration of globals changed by the runtime bootstrap.
        patch.setattr(sys, "stdout", sys.stdout)
        patch.setattr(sys, "stderr", sys.stderr)
        path = launcher.configure_frozen_runtime()
        stream = sys.stderr
        try:
            assert Path.cwd() == install
            assert os.environ["APP_PORT"] == "7011"
            assert os.environ["ODYSSEUS_DATA_DIR"] == str(data)
            assert path == data / "logs" / "launcher.log"
            print("early import failure", file=sys.stderr)
            assert "early import failure" in path.read_text(encoding="utf-8")
        finally:
            stream.close()


@pytest.mark.parametrize("failure", [RuntimeError("failed import"), SystemExit(1)])
def test_main_reports_startup_failures(failure, monkeypatch):
    monkeypatch.setattr(sys, "frozen", True, raising=False)
    monkeypatch.setenv("ODYSSEUS_NO_OPEN", "1")
    with mock.patch("launcher.configure_frozen_runtime", return_value=Path("launcher.log")), \
         mock.patch("launcher.run_server", side_effect=failure), \
         mock.patch("launcher.report_startup_error") as report:
        assert launcher.main() == 1
        report.assert_called_once_with(Path("launcher.log"))


def test_main_reports_failure_to_create_logs(monkeypatch):
    monkeypatch.setattr(sys, "frozen", True, raising=False)
    with mock.patch("launcher.configure_frozen_runtime", side_effect=PermissionError), \
         mock.patch("launcher.report_startup_error") as report:
        assert launcher.main() == 1
        report.assert_called_once_with(None)


def test_macos_uses_native_main_loop_and_reports_backend_failure(monkeypatch):
    monkeypatch.setenv("APP_PORT", "7860")
    icon = mock.Mock()
    # pystray owns the main loop and invokes setup on its backend thread.
    icon.run.side_effect = lambda setup: setup(icon)
    with mock.patch("launcher.create_tray_icon", return_value=icon), \
         mock.patch("launcher.run_server", side_effect=RuntimeError("startup failed")), \
         mock.patch("launcher.shutdown_requested"), \
         mock.patch("launcher.report_startup_error") as report:
        assert launcher.run_macos_desktop(Path("launcher.log")) == 1
        assert icon.visible is True
        icon.stop.assert_called_once()
        report.assert_called_once_with(Path("launcher.log"))


def test_macos_frozen_config_stays_outside_signed_bundle(tmp_path, monkeypatch):
    config = tmp_path / "User config"
    data = tmp_path / "User data"
    config.mkdir()
    (config / ".env").write_text(f'ODYSSEUS_DATA_DIR="{data.as_posix()}"\n', encoding="utf-8")
    with monkeypatch.context() as patch:
        patch.chdir(tmp_path)
        patch.setattr(sys, "platform", "darwin")
        patch.setattr(sys, "executable", str(tmp_path / "Read-only.app/Contents/MacOS/Odysseus"))
        patch.setenv("ODYSSEUS_CONFIG_DIR", str(config))
        patch.delenv("ODYSSEUS_DATA_DIR", raising=False)
        patch.delenv("APP_PORT", raising=False)
        patch.setattr(sys, "stdout", sys.stdout)
        patch.setattr(sys, "stderr", sys.stderr)
        path = launcher.configure_frozen_runtime()
        stream = sys.stderr
        try:
            assert Path.cwd() == config
            assert os.environ["APP_PORT"] == "7860"
            assert path == data / "logs/launcher.log"
            assert not (tmp_path / "Read-only.app").exists()
        finally:
            stream.close()

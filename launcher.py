# launcher.py
"""Entrypoint for the standalone Windows and macOS desktop applications.

Handles:
- Immediate GUI splash screen creation using tkinter.
- Suppressing console stream crashes in windowed GUI mode via NullWriter.
- Spawning system tray icon via pystray and Pillow (lazy-loaded).
- Auto-opening default browser pointing to the running backend.
- Launching the FastAPI server (importing and running app.py).
"""
import os
import sys
import threading
import time
import webbrowser
from pathlib import Path
import traceback

# PyInstaller multiprocessing children re-enter this executable with a private
# bootstrap argument. Consume it before splash/UI or application imports so a
# spawn-based worker does not relaunch the full desktop application.
if __name__ == "__main__":
    import multiprocessing
    multiprocessing.freeze_support()
    if getattr(sys, "frozen", False):
        from src.desktop_worker import dispatch
        if dispatch(sys.argv[1:]):
            raise SystemExit(0)

# Define a dummy NullWriter to suppress standard stream crashes (isatty etc.) in GUI mode
class NullWriter:
    def write(self, text):
        pass
    def flush(self):
        pass
    def isatty(self):
        return False

if sys.stdout is None:
    sys.stdout = NullWriter()
if sys.stderr is None:
    sys.stderr = NullWriter()


splash_root = None
active_server = None
shutdown_requested = threading.Event()

# If running from a frozen PyInstaller bundle, launch the splash screen IMMEDIATELY
if getattr(sys, 'frozen', False) and not os.getenv("ODYSSEUS_NO_OPEN") and sys.platform == "win32":
    def show_splash_instantly():
        global splash_root
        try:
            import tkinter as tk
            splash_root = tk.Tk()
            splash_root.title("Odysseus")
            splash_root.overrideredirect(True)
            splash_root.configure(bg="#1a1c23")

            # Accented borders
            splash_root.config(highlightbackground="#e06c75", highlightcolor="#e06c75", highlightthickness=1)

            w, h = 360, 160
            ws = splash_root.winfo_screenwidth()
            hs = splash_root.winfo_screenheight()
            x = (ws - w) // 2
            y = (hs - h) // 2
            splash_root.geometry(f"{w}x{h}+{x}+{y}")

            tk.Label(splash_root, text="⛵ Odysseus", font=("Segoe UI", 22, "bold"), bg="#1a1c23", fg="#e06c75").pack(pady=(22, 2))
            tk.Label(splash_root, text="Launching background services...", font=("Segoe UI", 10), bg="#1a1c23", fg="#d1d4e0").pack(pady=2)
            tk.Label(splash_root, text="First launch may take a few minutes.", font=("Segoe UI", 8, "italic"), bg="#1a1c23", fg="#5c6370").pack(pady=(12, 0))

            splash_root.attributes("-topmost", True)
            splash_root.mainloop()
        except Exception:
            pass

    # Launch the GUI splash screen immediately on a background thread
    threading.Thread(target=show_splash_instantly, daemon=True).start()


def create_tray_image():
    # Generate a beautiful 64x64 icon matching Odysseus brand red accent (#e06c75)
    from PIL import Image, ImageDraw
    image = Image.new('RGBA', (64, 64), (0, 0, 0, 0))
    dc = ImageDraw.Draw(image)
    accent_red = (224, 108, 117, 255)
    light_red = (224, 108, 117, 150)

    # Draw premium sailing boat
    dc.polygon([(32, 10), (32, 45), (12, 45)], fill=accent_red)
    dc.polygon([(32, 18), (32, 45), (48, 45)], fill=light_red)
    dc.polygon([(8, 48), (56, 48), (44, 56), (20, 56)], fill=accent_red)
    return image


def on_open_browser(icon, item, url):
    webbrowser.open(url)


def on_exit(icon, item):
    shutdown_requested.set()
    if active_server is not None:
        active_server.should_exit = True
    icon.stop()


def create_tray_icon(url):
    import pystray
    return pystray.Icon("Odysseus", create_tray_image(), "Odysseus", (
        pystray.MenuItem('Open Odysseus', lambda icon, item: on_open_browser(icon, item, url), default=True),
        pystray.MenuItem('Exit', on_exit),
    ))


def setup_system_tray(url):
    try:
        create_tray_icon(url).run()
    except Exception:
        traceback.print_exc()


def open_browser(url, server):
    # Uvicorn marks the server started only after application startup and
    # socket binding succeed. Slow first launches must not open a dead page.
    while not server.started:
        if server.should_exit:
            return
        time.sleep(0.1)
    if server.should_exit:
        return

    # Safely close the splash screen
    try:
        global splash_root
        if splash_root:
            splash_root.after(0, splash_root.destroy)
    except Exception:
        pass

    if not os.getenv("ODYSSEUS_NO_BROWSER"):
        webbrowser.open(url)


def browser_url(host, port):
    """Wildcard bind addresses are not browser destinations."""
    host = {"0.0.0.0": "127.0.0.1", "::": "::1"}.get(host, host)
    if ":" in host and not host.startswith("["):
        host = f"[{host}]"
    return f"http://{host}:{port}"


def configure_frozen_runtime():
    """Resolve config and logs independently of a shortcut's working folder."""
    from dotenv import load_dotenv
    from src.runtime_paths import get_default_data_dir

    install_dir = Path(sys.executable).resolve().parent
    if sys.platform == "darwin":
        # Never store configuration in a signed/read-only .app bundle.
        config_dir = Path(os.getenv("ODYSSEUS_CONFIG_DIR") or Path.home() / ".odysseus").expanduser().resolve()
        config_dir.mkdir(parents=True, exist_ok=True)
    else:
        config_dir = install_dir
    os.chdir(config_dir)
    load_dotenv(config_dir / ".env", encoding="utf-8-sig")
    data_dir = Path(os.getenv("ODYSSEUS_DATA_DIR") or get_default_data_dir()).expanduser().resolve()
    os.environ["ODYSSEUS_DATA_DIR"] = str(data_dir)
    log_dir = data_dir / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    log_path = log_dir / "launcher.log"
    # A file stream supports flush/isatty even in PyInstaller --noconsole mode.
    # Keep early import errors too; app.log is initialized later by app.py.
    stream = log_path.open("a", encoding="utf-8", buffering=1)
    sys.stdout = sys.stderr = stream
    os.environ.setdefault("APP_PORT", "7860" if sys.platform == "darwin" else "7011")
    return log_path


def report_startup_error(log_path):
    traceback.print_exc()
    message = "Odysseus could not start."
    if log_path:
        message += f"\n\nDetails are saved in:\n{log_path}"
    else:
        message += "\n\nCheck that your data folder is writable and the app was fully extracted."
    if os.getenv("ODYSSEUS_NO_OPEN"):
        return
    if sys.platform == "win32":
        import ctypes
        ctypes.windll.user32.MessageBoxW(None, message, "Odysseus startup failed", 0x10 | 0x40000)
    elif sys.platform == "darwin":
        import subprocess
        # Pass the text as argv so quotes and paths are never AppleScript code.
        subprocess.run(["/usr/bin/osascript", "-e",
                        'on run argv\ndisplay alert "Odysseus startup failed" message (item 1 of argv) as critical\nend run',
                        message], check=False)


def run_macos_desktop(log_path):
    """Cocoa owns the main thread; the backend runs in pystray's setup thread."""
    url = browser_url(os.getenv("APP_BIND", "127.0.0.1"), int(os.environ["APP_PORT"]))
    icon = create_tray_icon(url)
    result = [0]

    def serve(icon):
        icon.visible = True
        try:
            run_server()
        except (Exception, SystemExit):
            result[0] = 1
            report_startup_error(log_path)
        finally:
            icon.stop()

    try:
        icon.run(setup=serve)
    finally:
        shutdown_requested.set()
        if active_server is not None:
            active_server.should_exit = True
    return result[0]


def run_server():
    global active_server
    import uvicorn
    # Import the FastAPI app from app.py
    from app import app

    bind_host = os.getenv("APP_BIND", "127.0.0.1")
    bind_port = int(os.getenv("APP_PORT", "7011"))
    if not 1 <= bind_port <= 65535:
        raise ValueError("APP_PORT must be between 1 and 65535")
    url = browser_url(bind_host, bind_port)
    server = uvicorn.Server(uvicorn.Config(app, host=bind_host, port=bind_port, log_level="info"))
    active_server = server
    if shutdown_requested.is_set():
        active_server = None
        return

    if getattr(sys, 'frozen', False) and not os.getenv("ODYSSEUS_NO_OPEN"):
        # Start browser manager thread
        threading.Thread(target=open_browser, args=(url, server), daemon=True).start()
        # Start system tray manager thread
        if sys.platform != "darwin":
            threading.Thread(target=setup_system_tray, args=(url,), daemon=True).start()

    try:
        server.run()
        if not server.started:
            raise RuntimeError("The server stopped before startup completed. See app.log for details.")
    finally:
        server.should_exit = True
        active_server = None


def main():
    log_path = None
    try:
        if getattr(sys, 'frozen', False):
            log_path = configure_frozen_runtime()
            if sys.platform == "darwin" and not os.getenv("ODYSSEUS_NO_OPEN"):
                return run_macos_desktop(log_path)
        run_server()
        return 0
    except (Exception, SystemExit) as error:
        if isinstance(error, SystemExit) and error.code in (None, 0):
            return 0
        report_startup_error(log_path)
        return 1


if __name__ == "__main__":
    sys.exit(main())

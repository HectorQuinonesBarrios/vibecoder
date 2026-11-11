"""Dispatch Python subprocess requests without relaunching the desktop UI.

The frozen application is also sys.executable for built-in MCP servers and
agent Python subprocesses. Dispatch before importing app.py or changing cwd,
environment, or stdio; the parent already configured the child's boundary.
"""
import os
from pathlib import Path
import runpy
import sys


def restore_stdio():
    """Windowed Windows executables may need to reopen inherited pipe handles."""
    for name, number, mode in (("stdin", 0, "r"), ("stdout", 1, "w"), ("stderr", 2, "w")):
        if getattr(sys, name) is not None:
            continue
        if sys.platform == "win32":
            import ctypes
            import msvcrt
            get_handle = ctypes.windll.kernel32.GetStdHandle
            get_handle.restype = ctypes.c_void_p
            handle = get_handle(-10 - number)
            if handle and handle != ctypes.c_void_p(-1).value:
                fd = msvcrt.open_osfhandle(handle, os.O_RDONLY if mode == "r" else os.O_WRONLY)
                setattr(sys, name, os.fdopen(fd, mode, encoding="utf-8", buffering=1))
                continue
        setattr(sys, name, open(os.devnull, mode, encoding="utf-8"))


def dispatch(argv):
    """Return False for normal app launch; otherwise execute a worker request."""
    if not argv:
        return False
    restore_stdio()
    args = list(argv)
    if args[0] == "-I":
        # Frozen Python ignores PYTHONPATH/site directories at bootstrap. Keep
        # only the bundled module paths, as the Python tool requests isolation.
        root = Path(sys._MEIPASS).resolve()
        sys.path[:] = [p for p in sys.path if p and Path(p).resolve().is_relative_to(root)]
        args.pop(0)
    if len(args) >= 2 and args[0] == "-c":
        sys.argv = ["-c", *args[2:]]
        exec(compile(args[1], "<string>", "exec"), {"__name__": "__main__", "__builtins__": __builtins__})
        return True
    if len(args) >= 2 and args[0] == "-m":
        sys.argv = [args[1], *args[2:]]
        runpy.run_module(args[1], run_name="__main__", alter_sys=True)
        return True
    if args and not args[0].startswith("-"):
        script = Path(args[0]).resolve()
        root = Path(sys._MEIPASS).resolve()
        # Script execution is reserved for the application's bundled helpers.
        # User Python tool input uses -I -c with the existing containment path.
        allowed = script.is_relative_to(root / "mcp_servers") or script == root / "src/containment_worker.py"
        if allowed and script.is_file():
            sys.argv = [str(script), *args[1:]]
            runpy.run_path(str(script), run_name="__main__")
            return True
    raise SystemExit("Unsupported desktop subprocess arguments; use a separate Python installation for external scripts or pip.")

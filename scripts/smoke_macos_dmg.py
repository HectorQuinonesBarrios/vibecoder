"""Check a distributed DMG by starting its app from a read-only mount."""
import argparse
from pathlib import Path
import subprocess
import sys
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dmg", type=Path)
    args = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("DMG verification requires macOS.")
    image = args.dmg.resolve(strict=True)
    with tempfile.TemporaryDirectory(prefix="odysseus-mounted-") as temporary:
        mount = Path(temporary) / "volume"
        subprocess.run(["hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", str(mount), str(image)], check=True)
        try:
            app = mount / "Odysseus.app"
            subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
            subprocess.run([sys.executable, str(Path(__file__).with_name("smoke_desktop.py")),
                            "--executable", str(app / "Contents/MacOS/Odysseus")], check=True)
        finally:
            subprocess.run(["hdiutil", "detach", str(mount)], check=True)
    print("PASS: disk image integrity and read-only app launch")


if __name__ == "__main__":
    main()

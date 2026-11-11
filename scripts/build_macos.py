"""Build a standalone macOS app, optionally Developer ID sign and notarize it."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]


def run(*args, **kwargs):
    return subprocess.run([str(arg) for arg in args], check=True, **kwargs)


def notarize(path, profile):
    result = run("xcrun", "notarytool", "submit", path, "--keychain-profile", profile,
                 "--wait", "--output-format", "json", capture_output=True, text=True)
    status = json.loads(result.stdout)
    if status.get("status") != "Accepted":
        raise RuntimeError(f"Notarization was not accepted: {status.get('status')} (submission {status.get('id')})")


def validate_signing(identity, profile):
    if identity and not identity.startswith("Developer ID Application:"):
        raise ValueError("Use a Developer ID Application identity for distribution, not Apple Development.")
    if profile and not identity:
        raise ValueError("Notarization requires --sign-identity (Developer ID Application).")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sign-identity", default=os.getenv("ODYSSEUS_MAC_SIGN_IDENTITY"))
    parser.add_argument("--notary-profile", default=os.getenv("ODYSSEUS_NOTARY_PROFILE"),
                        help="Existing notarytool Keychain profile; never pass a password here")
    parser.add_argument("--python", type=Path, help="Use an existing build environment")
    parser.add_argument("--skip-install", action="store_true", help="Use already installed build dependencies")
    args = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("Build the Mac app on macOS; binaries cannot be cross-compiled here.")
    try:
        validate_signing(args.sign_identity, args.notary_profile)
    except ValueError as error:
        parser.error(str(error))

    os.chdir(ROOT)
    # Do not resolve a venv's interpreter symlink: that bypasses the venv.
    python = args.python.absolute() if args.python else ROOT / ".venv-build-macos/bin/python"
    if not python.exists():
        if args.python or args.skip_install:
            parser.error(f"Build interpreter not found: {python}")
        if sys.version_info < (3, 11):
            parser.error("Use Python 3.11+ to create the build environment (ODYSSEUS_BUILD_PYTHON).")
        run(sys.executable, "-m", "venv", ROOT / ".venv-build-macos")
    if not args.skip_install:
        run(python, "-m", "pip", "install", "--require-hashes", "--only-binary=:all:",
            "--no-deps", "-r", "requirements-bootstrap.txt")
        run(python, "-m", "pip", "install", "-r", "requirements.txt", "-r", "requirements-desktop-build.txt")
    run(python, "-c", "import PyInstaller, pystray, PIL, AppKit; import sys; assert sys.version_info >= (3, 11)")
    architecture = subprocess.check_output([str(python), "-c", "import platform; print(platform.machine())"], text=True).strip()
    if architecture != platform.machine():
        parser.error("Use a build interpreter matching this Mac's native architecture.")

    output = ROOT / "dist" / f"macos-{architecture}"
    env = dict(os.environ, ODYSSEUS_BUILD_MAC_APP="1")
    if args.sign_identity:
        env["ODYSSEUS_MAC_SIGN_IDENTITY"] = args.sign_identity
    else:
        env.pop("ODYSSEUS_MAC_SIGN_IDENTITY", None)
    run(python, "-m", "PyInstaller", "--noconfirm", "--clean", "--workpath", f"build/macos-{architecture}",
        "--distpath", output, "Odysseus.spec", env=env)
    app = output / "Odysseus.app"
    run("codesign", "--verify", "--deep", "--strict", "--verbose=2", app)
    run(python, "scripts/smoke_desktop.py", "--executable", app / "Contents/MacOS/Odysseus")

    # Staple the app before placing it in the DMG so offline installs retain
    # Apple's ticket. A notary rejection stops the build before packaging.
    if args.notary_profile:
        with tempfile.TemporaryDirectory(prefix="odysseus-notarize-") as temporary:
            archive = Path(temporary) / "Odysseus.zip"
            run("ditto", "-c", "-k", "--keepParent", app, archive)
            notarize(archive, args.notary_profile)
        run("xcrun", "stapler", "staple", app)
        run("xcrun", "stapler", "validate", app)
        run("spctl", "--assess", "--type", "execute", "--verbose=2", app)

    suffix = "notarized" if args.notary_profile else ("signed" if args.sign_identity else "unsigned")
    dmg = output / f"Odysseus-macos-{architecture}-{suffix}.dmg"
    with tempfile.TemporaryDirectory(prefix="odysseus-dmg-") as temporary:
        stage = Path(temporary)
        # ditto retains symlinks used by PyInstaller's Frameworks layout.
        run("ditto", app, stage / app.name)
        (stage / "Applications").symlink_to("/Applications")
        run("hdiutil", "create", "-volname", "Odysseus", "-srcfolder", stage,
            "-ov", "-format", "UDZO", dmg)
    if args.sign_identity:
        run("codesign", "--force", "--sign", args.sign_identity, "--timestamp", dmg)
        run("codesign", "--verify", "--verbose=2", dmg)
    if args.notary_profile:
        notarize(dmg, args.notary_profile)
        run("xcrun", "stapler", "staple", dmg)
        run("xcrun", "stapler", "validate", dmg)
    with dmg.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest()
    dmg.with_suffix(".dmg.sha256").write_text(f"{digest}  {dmg.name}\n", encoding="utf-8")
    print(f"\nBuilt {suffix} macOS {architecture} app: {app}\nDisk image: {dmg}")


if __name__ == "__main__":
    main()

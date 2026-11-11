# Desktop builds and release signing

Run builds on their target OS. Windows produces a per-user setup installer and
a portable ZIP; macOS produces a self-contained `.app` and a drag-to-Applications
DMG. Neither package requires an end-user Python installation. Optional
developer tools and model servers are not bundled.

## Local development builds

```powershell
powershell -ExecutionPolicy Bypass -File .\build-windows-portable.ps1
```

The Windows build requires Inno Setup 6 (`ISCC.exe`) to also produce
`dist\windows\Odysseus-Setup-unsigned.exe`. Pass `-SkipInstaller` to build only
the portable ZIP. The installer is per-user and does not require elevation.
It includes Start Menu shortcuts to explicitly refresh the default local Ollama
coding model and optionally enable or disable its weekly refresh task. The task
runs only while that user is signed in; Ollama and model weights remain separate
installs.

```bash
./build-macos-app.sh
# Reuse an existing environment when its build dependencies are installed:
./build-macos-app.sh --python .venv/bin/python --skip-install
```

Outputs are under `dist/windows`, `dist/macos-arm64`, or `dist/macos-x86_64`.
Names distinguish `unsigned`, `signed`, and `notarized` artifacts. Each archive
has a `.sha256` file. macOS applies an ad-hoc integrity signature even to the
build labeled unsigned; this does not identify a trusted publisher.

## macOS signing and notarization

Prerequisites: an Apple Developer ID Application certificate with its private
key in the build machine's Keychain, and an authenticated `notarytool` Keychain
profile. An Apple Development certificate is not a distribution certificate.
Install credentials outside the repository; never commit exported keys.

```bash
./build-macos-app.sh \
  --sign-identity 'Developer ID Application: Your Organization (TEAMID)' \
  --notary-profile 'odysseus-release'
```

`ODYSSEUS_MAC_SIGN_IDENTITY` and `ODYSSEUS_NOTARY_PROFILE` provide the same
options. The build signs bundled native code through PyInstaller's hardened
runtime support, verifies the app, submits it to Apple, and requires an
`Accepted` status. It staples the app before creating the DMG, then signs,
notarizes, and staples the DMG. Any failure stops the release. No blanket
library-validation or executable-memory exceptions are enabled.

Create the Keychain profile using Apple's interactive `xcrun notarytool
store-credentials` flow. See [Apple's notarization documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
and [PyInstaller's macOS signing notes](https://pyinstaller.org/en/stable/feature-notes.html#macos-binary-code-signing).

## Windows signing

Install a trusted Authenticode code-signing certificate in the current user's
Personal certificate store, with access to its private key through your token,
certificate provider, or managed signing setup. Install Windows SDK Signing
Tools. No PFX passwords are put on the command line.

```powershell
.\build-windows-portable.ps1 -Sign -CertificateThumbprint 'YOUR_40_CHARACTER_THUMBPRINT'
```

`ODYSSEUS_WINDOWS_CERT_THUMBPRINT` can supply the thumbprint. The script signs
`Odysseus.exe` with SHA-256, requests an RFC 3161 timestamp, verifies the
Authenticode chain and timestamp, and then packages a `signed.zip`. Use
`-TimestampServer` for your certificate provider's timestamp service. Missing
credentials, SDK tools, or failed verification stop the build. A signature
does not guarantee immediate Microsoft SmartScreen reputation.

See [Microsoft SignTool documentation](https://learn.microsoft.com/en-us/windows/win32/seccrypto/signtool).

## Validation and CI

```bash
python scripts/smoke_desktop.py --executable PATH_TO_EXECUTABLE
python scripts/smoke_desktop.py --executable PATH_TO_EXECUTABLE --ui
python scripts/smoke_macos_dmg.py PATH_TO_DMG
```

The smoke check creates an isolated data/config directory, starts the app,
checks frontend assets, creates an account, restarts, and verifies login.
`--ui` initializes the actual tray/menu-bar UI without opening a browser.
It does not prove every menu interaction, installer policy, or Windows
SmartScreen/Gatekeeper download behavior. The DMG check runs from a read-only
mount to catch writes into the signed app and missing external dependencies.

`.github/workflows/desktop.yml` runs native source tests and builds on Windows
x64, macOS arm64, and macOS Intel. Jobs upload only packages that passed checks;
they do not publish releases or use signing secrets. Run it manually or on the
desktop development branch. Signed releases should run on a controlled machine
with the appropriate certificate provider/Keychain access.

Before a public release, also test a downloaded signed package on a clean
machine, exercise Open/Exit and port-conflict handling, and confirm coding
tools work with a project path containing spaces. Do not label a package
Windows-validated until its native job or clean-machine test has passed.

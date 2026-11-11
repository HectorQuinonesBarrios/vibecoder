#!/bin/bash
# Build a downloadable macOS launcher app + .dmg for Odysseus.
#
#   ./build-macos-launcher.sh
#
# Produces:
#   dist/Odysseus.app   — double-click: starts the local server (using this
#                         repo's venv) and opens the UI in an app-style window.
#   dist/Odysseus.dmg   — drag-to-Applications disk image (the downloadable).
#
# This is a *launcher* wrapper: it drives the venv we set up in this repo, it
# does not bundle Python. The install path is baked into the app at build time,
# so rebuild if you move the repo. Override the port with ODYSSEUS_PORT.
set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="Odysseus"
INSTALL_DIR="$REPO_DIR"
PORT="${ODYSSEUS_PORT:-7860}"
DIST="$REPO_DIR/dist"
APP="$DIST/$APP_NAME.app"

echo "Building $APP_NAME.app"
echo "  install dir: $INSTALL_DIR"
echo "  port:        $PORT"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# ── Icon (best effort) -- center-crop the branding image to a square .icns ──
if [ -f "$REPO_DIR/assets/branding/odysseus.jpg" ] && command -v sips >/dev/null 2>&1; then
  TMPIMG="$(mktemp -d)"
  # Center-crop to a square, scale to 512 (sips' icns encoder caps at 512), and
  # let sips emit the .icns directly: more robust across macOS versions than
  # building an .iconset by hand.
  sips -c 720 720 "$REPO_DIR/assets/branding/odysseus.jpg" --out "$TMPIMG/sq.png" >/dev/null 2>&1 || cp "$REPO_DIR/assets/branding/odysseus.jpg" "$TMPIMG/sq.png"
  sips -z 512 512 "$TMPIMG/sq.png" --out "$TMPIMG/icon.png" >/dev/null 2>&1
  if sips -s format icns "$TMPIMG/icon.png" --out "$APP/Contents/Resources/odysseus.icns" >/dev/null 2>&1; then
    echo "  icon:        odysseus.icns"
  else
    echo "  icon:        (skipped - conversion failed)"
  fi
  rm -rf "$TMPIMG"
else
  echo "  icon:        (skipped - no assets/branding/odysseus.jpg)"
fi
cp -R "$REPO_DIR/licenses" "$APP/Contents/Resources/licenses"
cp "$REPO_DIR/THIRD_PARTY_PROVENANCE.json" "$REPO_DIR/ACKNOWLEDGMENTS.md" "$APP/Contents/Resources/"

# ── Info.plist ──
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>     <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>      <string>com.odysseus.launcher</string>
    <key>CFBundleVersion</key>         <string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleExecutable</key>      <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>        <string>odysseus</string>
    <key>LSMinimumSystemVersion</key>  <string>11.0</string>
    <key>NSHighResolutionCapable</key> <true/>
    <key>LSUIElement</key>             <false/>
</dict>
</plist>
PLIST

# ── Launcher executable (placeholders filled below) ──
cat > "$APP/Contents/MacOS/$APP_NAME.tmpl" <<'LAUNCHER'
#!/bin/bash
# Odysseus.app — choose a project, start the local server, and open the UI in an app window.
# INSTALL_DIR and PORT are written as shell-escaped assignments by the builder.
URL="http://127.0.0.1:${PORT}"
# uvicorn is started with --port below, but APP_PORT is what the app itself
# reads when it needs to build a URL for this instance (internal_api_base(),
# companion pairing, the MCP OAuth callback), so export it as well.
export APP_PORT="$PORT"
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

UVICORN="$INSTALL_DIR/venv/bin/uvicorn"
LOG="$INSTALL_DIR/logs/odysseus-app.log"
SETUP_LAUNCHER="$INSTALL_DIR/start-macos.sh"

notify() { /usr/bin/osascript -e "display notification \"$1\" with title \"Odysseus\"" >/dev/null 2>&1; }
die_gui() {
  /usr/bin/osascript -e "display dialog \"$1\" with title \"Odysseus\" buttons {\"OK\"} default button 1 with icon stop" >/dev/null 2>&1
  exit 1
}

[ -x "$UVICORN" ] || [ -x "$SETUP_LAUNCHER" ] || die_gui "Odysseus setup launcher is missing from:

$INSTALL_DIR

Rebuild the app from the Odysseus project folder with ./build-macos-launcher.sh."

# Open the UI in a chrome-less app window (Chromium browsers), else default browser.
open_ui() {
  local b base exe bin
  for b in "Google Chrome" "Microsoft Edge" "Brave Browser" "Chromium"; do
    for base in "/Applications" "$HOME/Applications"; do
      if [ -d "$base/$b.app" ]; then
        exe="$(/usr/bin/defaults read "$base/$b.app/Contents/Info" CFBundleExecutable 2>/dev/null)"
        bin="$base/$b.app/Contents/MacOS/$exe"
        if [ -x "$bin" ]; then
          "$bin" --app="$URL" --new-window >/dev/null 2>&1 &
          return 0
        fi
      fi
    done
  done
  /usr/bin/open "$URL"
}

is_ready() {
  /usr/bin/curl --noproxy '*' -fsS --max-time 2 "$URL/api/health" 2>/dev/null |
    /usr/bin/grep -Eq '"status"[[:space:]]*:[[:space:]]*"healthy"'
}

mkdir -p "$INSTALL_DIR/logs"

# Already running? Just open the UI; the in-app Workspace picker can switch projects.
if is_ready; then
  open_ui
  exit 0
fi

# Pick a coding project before starting the server. Odysseus validates this
# value again in /api/workspace/default before binding file/shell tools.
WORKSPACE="$(/usr/bin/osascript <<'APPLESCRIPT' 2>/dev/null || true
try
  set projectFolder to choose folder with prompt "Choose a project for the Odysseus coding agent"
  return POSIX path of projectFolder
on error number -128
  return ""
end try
APPLESCRIPT
)"
WORKSPACE="$(printf '%s' "$WORKSPACE" | tr -d '\r\n')"
if [ -n "$WORKSPACE" ]; then
  export ODYSSEUS_WORKSPACE_DEFAULT="$WORKSPACE"
  notify "Project selected: $(basename "$WORKSPACE")"
else
  unset ODYSSEUS_WORKSPACE_DEFAULT
  notify "No project selected — choose Workspace in Agent mode"
fi

# First launch: reuse the native installer so dependency setup stays in one
# place. It runs in the background; this app wrapper still owns readiness,
# opening the app window, and stopping the server when the app quits.
FIRST_ADMIN_PASSWORD=""
STARTUP_TIMEOUT=120
if [ ! -x "$UVICORN" ] || [ ! -f "$INSTALL_DIR/venv/.requirements_hash" ]; then
  STARTUP_TIMEOUT=1800
  notify "Installing Odysseus — this may take a few minutes"
  if [ ! -f "$INSTALL_DIR/data/auth.json" ] && [ -z "${ODYSSEUS_ADMIN_PASSWORD:-}" ]; then
    FIRST_ADMIN_PASSWORD="$(/usr/bin/openssl rand -hex 18)"
    export ODYSSEUS_ADMIN_USER="${ODYSSEUS_ADMIN_USER:-admin}"
    export ODYSSEUS_ADMIN_PASSWORD="$FIRST_ADMIN_PASSWORD"
  fi
  (
    cd "$INSTALL_DIR" || exit 1
    ODYSSEUS_NO_OPEN=1 ODYSSEUS_PORT="$PORT" ODYSSEUS_HOST=127.0.0.1 ./start-macos.sh
  ) >>"$LOG" 2>&1 &
  SERVER_PID=$!
else
  notify "Starting…"
  cd "$INSTALL_DIR" || die_gui "Install folder not found: $INSTALL_DIR"
  if [ "$(uname -m)" = "arm64" ]; then
    arch -arm64 "$UVICORN" app:app --host 127.0.0.1 --port "$PORT" >>"$LOG" 2>&1 &
  else
    "$UVICORN" app:app --host 127.0.0.1 --port "$PORT" >>"$LOG" 2>&1 &
  fi
  SERVER_PID=$!
fi

# Quitting the app stops the server it started.
cleanup() { kill "$SERVER_PID" 2>/dev/null || true; }
trap cleanup EXIT
trap 'exit 0' TERM INT

# Wait for the health response; first-time dependency installation gets longer.
READY=0
DEADLINE=$((SECONDS + STARTUP_TIMEOUT))
while [ "$SECONDS" -lt "$DEADLINE" ]; do
  kill -0 "$SERVER_PID" 2>/dev/null || die_gui "Odysseus failed to start. Log:
$LOG"
  is_ready && { READY=1; break; }
  sleep 1
done

if [ "$READY" = "1" ]; then
  open_ui
  if [ -n "$FIRST_ADMIN_PASSWORD" ]; then
    /usr/bin/osascript -e "display dialog \"First login for Odysseus:\\n\\nUsername: $ODYSSEUS_ADMIN_USER\\nPassword: $FIRST_ADMIN_PASSWORD\\n\\nSave this password before closing this dialog. You can change it in Settings after logging in.\" with title \"Odysseus first setup\" buttons {\"OK\"} default button 1 with icon note" >/dev/null 2>&1
  fi
else
  die_gui "Odysseus did not become ready within $STARTUP_TIMEOUT seconds. Log:
$LOG

Check the log and launch the app again to retry."
fi
wait "$SERVER_PID"
LAUNCHER

{
  printf '#!/bin/bash\nINSTALL_DIR=%q\nPORT=%q\n' "$INSTALL_DIR" "$PORT"
  cat "$APP/Contents/MacOS/$APP_NAME.tmpl"
} > "$APP/Contents/MacOS/$APP_NAME"
rm -f "$APP/Contents/MacOS/$APP_NAME.tmpl"
chmod +x "$APP/Contents/MacOS/$APP_NAME"

# Refresh Finder's icon cache for the new bundle.
touch "$APP"

# ── .dmg (drag-to-Applications) ──
echo "Packaging dist/$APP_NAME.dmg"
STAGE="$(mktemp -d)/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DIST/$APP_NAME.dmg"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DIST/$APP_NAME.dmg" >/dev/null
rm -rf "$STAGE"

echo ""
echo "Done:"
echo "  $APP"
echo "  $DIST/$APP_NAME.dmg"
echo ""
echo "Run it:        open '$APP'"
echo "Install:       open '$DIST/$APP_NAME.dmg'  (drag Odysseus to Applications)"

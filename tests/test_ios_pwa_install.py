import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_ios_home_screen_install_entry_is_present_and_accessible():
    markup = (ROOT / "static/index.html").read_text(encoding="utf-8")
    workspace = (ROOT / "static/js/workspace.js").read_text(encoding="utf-8")

    assert 'id="sidebar-ios-install-btn"' in markup
    assert "_isIOSDevice() && !_isInstalledPWA()" in workspace
    assert "navigator.standalone === true" in workspace
    assert "Add to Home Screen" in workspace
    assert "over HTTPS" in workspace


def test_ios_home_screen_install_manifest_has_required_assets():
    manifest = json.loads((ROOT / "static/manifest.json").read_text(encoding="utf-8"))
    index = (ROOT / "static/index.html").read_text(encoding="utf-8")

    assert manifest["display"] == "standalone"
    assert manifest["start_url"] == "/"
    assert 'rel="apple-touch-icon"' in index
    assert 'apple-mobile-web-app-capable' in index
    for icon in manifest["icons"]:
        assert (ROOT / "static" / icon["src"]).is_file()
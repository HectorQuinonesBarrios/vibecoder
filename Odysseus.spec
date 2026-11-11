# -*- mode: python ; coding: utf-8 -*-
import os
import sys
from pathlib import Path

mac_app = sys.platform == 'darwin' and os.environ.get('ODYSSEUS_BUILD_MAC_APP') == '1'
signing_identity = os.environ.get('ODYSSEUS_MAC_SIGN_IDENTITY') if mac_app else None

a = Analysis(
    ['launcher.py'],
    pathex=[],
    binaries=[],
    datas=[('licenses', 'licenses'), ('LICENSE', '.'), ('THIRD_PARTY_PROVENANCE.json', '.'), ('ACKNOWLEDGMENTS.md', '.'), ('static', 'static'), ('scripts', 'scripts'), ('mcp_servers', 'mcp_servers'), ('src/containment_worker.py', 'src'), ('services/hwfit/data', 'services/hwfit/data'), ('config', 'config'), ('resources', 'resources'), ('HARNESS_VERSION', '.'), ('.env.example', '.')],
    # These service exports are resolved with import_module at runtime.
    hiddenimports=['services.search', 'services.docs', 'services.research',
                   'services.memory', 'services.shell',
                   'uvicorn.logging', 'uvicorn.loops.asyncio',
                   'uvicorn.protocols.http.h11_impl', 'uvicorn.lifespan.on']
                  + ['mcp_servers.' + p.stem for p in Path('mcp_servers').glob('*.py')]
                  + ['src.containment_worker'],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='Odysseus',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=signing_identity,
    entitlements_file=None,
    icon=['static/icon.ico'],
)
coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name='Odysseus',
)

if mac_app:
    app = BUNDLE(
        coll,
        name='Odysseus.app',
        icon='static/icon.ico',
        bundle_identifier=os.environ.get('ODYSSEUS_MAC_BUNDLE_ID', 'com.odysseus.desktop'),
        version='1.0.3',
        info_plist={
            'CFBundleShortVersionString': '1.0.3',
            'LSMinimumSystemVersion': '14.0',
            'LSUIElement': True,
            'NSHighResolutionCapable': True,
        },
    )

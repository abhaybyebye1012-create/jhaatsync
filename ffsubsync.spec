# -*- mode: python ; coding: utf-8 -*-

block_cipher = None

# -----------------------------------------------------------------
# Adjust the entry point if ffsubsync’s main module is not named
# `ffsubsync.py`. If the project uses a package, point to the
# appropriate `.py` file (e.g. `ffsubsync/__main__.py`).
# -----------------------------------------------------------------
a = Analysis(
    ["ffsubsync.py"],               # <-- main script
    pathex=["."],
    binaries=[],
    datas=[
        ("icon.png", "."),          # copy your 256×256 PNG into the bundle
        ("ffsubsync.cfg", "."),    # any extra data files you need
    ],
    hiddenimports=["PyQt5.sip"],    # required for the Qt5 binding
    hookspath=[],
    runtime_hooks=[],
    excludes=[],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

# -----------------------------------------------------------------
# Collect Qt platform and image‑format plugins – they are not
# automatically added when building a GUI app.
# -----------------------------------------------------------------
qt_dir = os.path.join(os.path.dirname(PyQt5.__file__), "Qt")
plugins = [
    ("platforms", os.path.join(qt_dir, "plugins", "platforms")),
    ("imageformats", os.path.join(qt_dir, "plugins", "imageformats")),
    ("styles", os.path.join(qt_dir, "plugins", "styles")),
]

for name, src in plugins:
    if os.path.isdir(src):
        a.datas += collect_data_files(src, strip_root=False)
        a.binaries += collect_binaries(src, strip_root=False)

pyz = PYZ(a.pure, a.zipped_data,
          cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.zipfiles,
    a.datas,
    [],
    exclude_binaries=True,
    name="ffsubsync",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,           # optional – makes the binary smaller
    console=False,      # windowed GUI (no terminal)
    icon="icon.png",
)

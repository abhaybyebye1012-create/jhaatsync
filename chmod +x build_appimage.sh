#!/usr/bin/env bash
# -----------------------------------------------------------------
# Full build script – should be run *inside* the Docker container
# defined by Dockerfile.build.
#
# It performs the following steps:
#   1️⃣  (optional) builds or downloads a static ffmpeg binary
#   2️⃣  installs Python deps + pyinstaller
#   3️⃣  runs pyinstaller on ffsync.spec (one‑file, windowed)
#   4️⃣  creates the AppDir layout (binary, plugins, static ffmpeg,
#       desktop entry, icon)
#   5️⃣  calls appimage‑builder to embed the runtime and create
#       ffsubsync‑x86_64.AppImage
# -----------------------------------------------------------------
set -euo pipefail

# -----------------------------------------------------------------
# 0️⃣  Resolve paths (the script runs from the repository root)
# -----------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# -----------------------------------------------------------------
# 1️⃣  (Optional) Get a static ffmpeg binary.
#     If you prefer to compile your own, replace the block below
#     with the ffmpeg‑configure / make commands.
# -----------------------------------------------------------------
STATIC_FFMPEG_TAR="ffmpeg-static-linux64.tar.xz"
STATIC_FFMPEG_DIR="ffmpeg-static-linux64"

# Download the static ffmpeg bundle from the official release site.
# The version below (ffmpeg‑5.1.2) is just an example – feel free
# to replace it with the newest at the time.
if [ ! -f "$STATIC_FFMPEG_TAR" ]; then
    echo "Downloading static ffmpeg (≈ 30 MiB)..."
    curl -L -o "$STATIC_FFMPEG_TAR" \
        https://johnvansickle.com/ffmpeg/releases/ffmpeg-5.1.2-static-linux64.tar.xz
fi

if [ ! -d "$STATIC_FFMPEG_DIR" ]; then
    echo "Extracting static ffmpeg..."
    tar xf "$STATIC_FFMPEG_TAR"
fi

# -----------------------------------------------------------------
# 2️⃣  Install Python dependencies
# -----------------------------------------------------------------
echo "Upgrading pip & installing requirements..."
python3 -m pip install --upgrade pip setuptools wheel
python3 -m pip install -r requirements.txt
python3 -m pip install pyinstaller

# -----------------------------------------------------------------
# 3️⃣  Build the PyInstaller one‑file bundle
# -----------------------------------------------------------------
echo "Running PyInstaller..."
pyinstaller --clean --onefile --windowed ffsubsync.spec

# The resulting binary will be in `dist/ffsubsync`
PY_BIN="dist/ffsubsync"

# -----------------------------------------------------------------
# 4️⃣  Assemble the AppDir (temporary location)
# -----------------------------------------------------------------
APPDIR="/tmp/AppDir"
echo "Creating AppDir at $APPDIR ..."
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin"
mkdir -p "$APPDIR/usr/lib/qt5/plugins/platforms"
mkdir -p "$APPDIR/usr/lib/qt5/plugins/imageformats"
mkdir -p "$APPDIR/usr/share/applications"
mkdir -p "$APPDIR/usr/share/icons/hicolor/256x256/apps"
mkdir -p "$APPDIR/AppRun"

# Copy the PyInstaller binary
cp "$PY_BIN" "$APPDIR/usr/bin/"

# Copy the static ffmpeg binary (adds the plain `ffmpeg` command)
mkdir -p "$APPDIR/usr/bin"
cp "${STATIC_FFMPEG_DIR}/bin/ffmpeg" "$APPDIR/usr/bin/"

# -----------------------------------------------------------------
# 4.1  Copy Qt platform / image‑format plugins that are *outside*
#        PyInstaller’s archive.  They are needed at runtime.
# -----------------------------------------------------------------
# Detect where PyQt5 was installed (inside the venv/venv‑like env)
PYQT_PLUGINS=$(python3 - <<'PY'
import PyQt5, os, pathlib
qt_dir = pathlib.Path(PyQt5.__file__).resolve().parent / "Qt" / "plugins"
print(str(qt_dir))
PY
)

# Platform plugin (`libqxcb.so`)
cp "$PYQT_PLUGINS/platforms/libqxcb.so" \
   "$APPDIR/usr/lib/qt5/plugins/platforms/"

# Image format plugins (jpeg, png, gif, webp, tiff, ... )
for fmt in qjpeg qpng gtiff qgif qwebp; do
    PLUGIN_PATH="$PYQT_PLUGINS/imageformats/lib${fmt}.so"
    if [ -f "$PLUGIN_PATH" ]; then
        cp "$PLUGIN_PATH" "$APPDIR/usr/lib/qt5/plugins/imageformats/"
    fi
done

# -----------------------------------------------------------------
# 4.2  Desktop entry & icon
# -----------------------------------------------------------------
cat > "$APPDIR/usr/share/applications/ffsubsync.desktop" <<'EOF'
[Desktop Entry]
Name=ffsubsync
Comment=Extract & sync subtitles using FFmpeg
Exec=AppRun %U
Terminal=false
Type=Application
Icon=ffsubsync
Categories=Video;AudioVideo;
MimeType=
Keywords=video;subtitle;ffmpeg;extract;
EOF

mkdir -p "$APPDIR/usr/share/icons/hicolor/256x256/apps"
cp icon.png "$APPDIR/usr/share/icons/hicolor/256x256/apps/ffsubsync.png"

# -----------------------------------------------------------------
# 4.3  AppRun – tiny launcher that wires everything together
# -----------------------------------------------------------------
cat > "$APPDIR/AppRun" <<'EOF'
#!/usr/bin/env bash
# The directory that contains this script is the root of the AppImage.
APPDIR="$(cd "$(dirname "$0")" && pwd)"

# Prepend the AppDir's binary locations to the environment.
export PATH="${APPDIR}/usr/bin:${PATH}"
export QT_PLUGIN_PATH="${APPDIR}/usr/lib/qt5/plugins:${QT_PLUGIN_PATH:-}"
export XDG_DATA_DIRS="${APPDIR}/usr/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"

# Run the actual ffsync binary.
exec "${APPDIR}/usr/bin/ffsubsync" "$@"
EOF
chmod +x "$APPDIR/AppRun"

# -----------------------------------------------------------------
# 5️⃣  Download the official AppImage runtime (glibc 2.28)
# -----------------------------------------------------------------
RUNTIME_URL="https://github.com/AppImage/AppImageKit/releases/download/continuous/appimage-runtime-x86_64.AppImage"
RUNTIME_FILE="${HOME}/appimage-runtime.AppImage"

if [ ! -f "$RUNTIME_FILE" ]; then
    echo "Downloading AppImage runtime..."
    curl -L -o "$RUNTIME_FILE" "$RUNTIME_URL"
    chmod +x "$RUNTIME_FILE"
fi

# -----------------------------------------------------------------
# 6️⃣  Build the final .AppImage using appimage‑builder Docker image
# -----------------------------------------------------------------
echo "Running appimage-builder..."
docker run --rm -v "${PWD}:/src" -v "${HOME}:/out" \
    ghcr.io/appimage/appimage-builder:latest \
    appimage-builder \
    --config /src/appimage.yml \
    --runtime-appimage /out/appimage-runtime.AppImage \
    -o /src/ffsubsync-x86_64.AppImage

echo "✅  AppImage built: /src/ffsubsync-x86_64.AppImage"

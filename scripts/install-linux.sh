#!/bin/sh
# Instalador de Yeflix para Linux.
#
# Uso:
#   curl -fsSL https://raw.githubusercontent.com/yeflixlite/Yeflix/main/scripts/install-linux.sh | sh
#
# Descarga el portable oficial (que ya incluye libmpv y todas sus
# dependencias), lo instala en ~/.local/opt/yeflix y crea el acceso directo
# en el menu de aplicaciones. No necesitas instalar nada mas.

set -eu

REPO="yeflixlite/Yeflix"
FALLBACK_TAG="v1.0.3"
DEST="$HOME/.local/opt/yeflix"
BIN_DIR="$HOME/.local/bin"
DESKTOP_DIR="$HOME/.local/share/applications"

say() { printf '%s\n' "$*"; }
fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }

# --- Comprobaciones ---------------------------------------------------------

ARCH=$(uname -m 2>/dev/null || echo unknown)
case "$ARCH" in
  x86_64|amd64) ;;
  *) fail "Yeflix solo esta disponible para Linux x86_64 (tu equipo es $ARCH)." ;;
esac

command -v tar >/dev/null 2>&1 || fail "falta 'tar' en el sistema."

if command -v curl >/dev/null 2>&1; then
  DOWNLOAD() { curl -fsSL --proto '=https' --tlsv1.2 -o "$1" "$2"; }
elif command -v wget >/dev/null 2>&1; then
  DOWNLOAD() { wget -q -O "$1" "$2"; }
else
  fail "necesitas 'curl' o 'wget' para descargar Yeflix."
fi

# --- Version ---------------------------------------------------------------

TAG=""
if command -v curl >/dev/null 2>&1; then
  TAG=$(curl -fsSL --proto '=https' --tlsv1.2 \
    "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
    | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    | head -n 1 || true)
fi
[ -n "$TAG" ] || TAG="$FALLBACK_TAG"
VERSION=${TAG#v}

ASSET="Yeflix-${VERSION}-Linux-x64.tar.gz"
URL="https://github.com/$REPO/releases/download/$TAG/$ASSET"

# --- Descarga y extraccion -------------------------------------------------

TMP=$(mktemp -d 2>/dev/null || mktemp -d -t yeflix)
trap 'rm -rf "$TMP"' EXIT INT TERM

say "Descargando Yeflix $VERSION..."
DOWNLOAD "$TMP/$ASSET" "$URL" || fail "no se pudo descargar $URL"

say "Instalando en $DEST..."
mkdir -p "$TMP/extract"
tar -xzf "$TMP/$ASSET" -C "$TMP/extract" || fail "el archivo descargado esta danado."

SRC=$(find "$TMP/extract" -maxdepth 1 -type d -name 'Yeflix-*' | head -n 1)
[ -n "$SRC" ] || fail "no se encontro la carpeta de Yeflix dentro del archivo."
[ -f "$SRC/yeflix" ] || fail "el paquete no contiene el ejecutable 'yeflix'."

rm -rf "$DEST"
mkdir -p "$DEST"
cp -a "$SRC"/. "$DEST"/
chmod +x "$DEST/yeflix"
if [ -f "$DEST/yeflix.bin" ]; then
  chmod +x "$DEST/yeflix.bin"
fi

# --- Acceso directo --------------------------------------------------------

mkdir -p "$BIN_DIR" "$DESKTOP_DIR"
ln -sf "$DEST/yeflix" "$BIN_DIR/yeflix"

cat > "$DESKTOP_DIR/yeflix.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Yeflix
GenericName=Reproductor de video
Comment=Anime, peliculas y series en espanol
Exec=$DEST/yeflix %U
Icon=$DEST/yeflix.png
Terminal=false
Categories=AudioVideo;Video;Player;
Keywords=anime;peliculas;series;streaming;
StartupWMClass=yeflix
EOF
chmod +x "$DESKTOP_DIR/yeflix.desktop"

command -v update-desktop-database >/dev/null 2>&1 \
  && update-desktop-database -q "$DESKTOP_DIR" 2>/dev/null || true

# --- Resumen ---------------------------------------------------------------

say ""
say "Yeflix $VERSION se instalo correctamente."
say "  App:    $DEST/yeflix"
say "  Menu:   busca \"Yeflix\" en tus aplicaciones"

case ":${PATH}:" in
  *":$BIN_DIR:"*)
    say "  Comando: yeflix"
    ;;
  *)
    say "  Comando: $BIN_DIR/yeflix"
    say ""
    say "Para usar el comando 'yeflix' desde cualquier terminal, agrega esto"
    say "al final de tu ~/.bashrc o ~/.zshrc:"
    say ""
    say "  export PATH=\"\$HOME/.local/bin:\$PATH\""
    ;;
esac
say ""

#!/bin/sh
# Instalador local de Yeflix para Linux.
# Instala la app en ~/.local/opt/yeflix y crea el acceso en el menú.
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
DEST="$HOME/.local/opt/yeflix"
BIN_DIR="$HOME/.local/bin"
DESKTOP_DIR="$HOME/.local/share/applications"
ICON_DIR="$HOME/.local/share/icons/hicolor/512x512/apps"

if [ ! -x "$HERE/yeflix" ]; then
  echo "Error: no se encontró el ejecutable 'yeflix' junto a este instalador." >&2
  exit 1
fi

mkdir -p "$DEST" "$BIN_DIR" "$DESKTOP_DIR" "$ICON_DIR"
rm -rf "$DEST/lib" "$DEST/data"
cp "$HERE/yeflix" "$DEST/yeflix"
cp -r "$HERE/lib" "$DEST/lib"
cp -r "$HERE/data" "$DEST/data"
chmod +x "$DEST/yeflix"

if [ -f "$HERE/yeflix.png" ]; then
  cp "$HERE/yeflix.png" "$ICON_DIR/yeflix.png"
fi

ln -sf "$DEST/yeflix" "$BIN_DIR/yeflix"

cat > "$DESKTOP_DIR/yeflix.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Yeflix
GenericName=Reproductor de video
Comment=Anime, películas y series en español
Exec=$DEST/yeflix %U
Icon=yeflix
Terminal=false
Categories=AudioVideo;Video;Player;
Keywords=anime;peliculas;series;streaming;
StartupWMClass=yeflix
EOF

chmod +x "$DESKTOP_DIR/yeflix.desktop"
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q "$DESKTOP_DIR" || true

echo ""
echo "Yeflix se instaló correctamente."
echo "  App:     $DEST/yeflix"
echo "  Comando: yeflix  (si ~/.local/bin está en tu PATH)"
echo "  Menú:    busca \"Yeflix\" en tus aplicaciones"
echo ""
echo "Nota: si el reproductor no inicia, instala libmpv con el gestor"
echo "de paquetes de tu distribución (paquete 'libmpv' o 'mpv')."

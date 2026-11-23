#!/bin/bash
set -euo pipefail

# Packt die App (DoMa Talk.app) in ein Disk-Image (DMG). Beim Öffnen zeigt Finder die App und den
# Ordner Programme: zum Installieren die App auf Programme ziehen, wie bei anderen Mac-Apps.
# Wer Platz sparen will, zieht sie stattdessen auf ein anderes Laufwerk.
#
# Verwendung: scripts/make-dmg.sh [Pfad/zu/App.app] [Zielordner]
#   Standard: die App von ./build.sh im Repo-Ordner (Name aus project.yml) nach ./dist
#
# Mit dmgbuild (python3 -m pip install dmgbuild) bekommt das Fenster seine Anordnung und
# den Hintergrund aus scripts/dmg/. Ohne dmgbuild enthält das Image dieselben zwei Einträge
# in der Standardansicht von Finder.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEFAULT_NAME="$(sed -n 's/^ *PRODUCT_NAME: *"\{0,1\}\([^"]*\)"\{0,1\} *$/\1/p' "$REPO_DIR/BlitztextMac/project.yml" | head -1)"
APP_PATH="${1:-$REPO_DIR/$DEFAULT_NAME.app}"
OUT_DIR="${2:-$REPO_DIR/dist}"

if [ ! -d "$APP_PATH" ]; then
    echo "❌ App nicht gefunden: $APP_PATH"
    echo "   Zuerst ./build.sh ausführen oder den Pfad zur App angeben."
    exit 1
fi

APP_PATH="$(cd "$(dirname "$APP_PATH")" && pwd)/$(basename "$APP_PATH")"
APP_NAME="$(basename "$APP_PATH" .app)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)"
mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"
# No spaces in the file name: "DoMa Talk" becomes DoMa-Talk-1.18.1.dmg.
DMG_PATH="$OUT_DIR/${APP_NAME// /-}${VERSION:+-$VERSION}.dmg"
rm -f "$DMG_PATH"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

if python3 -c 'import dmgbuild' 2>/dev/null; then
    echo "💿 Baue DMG mit Fenster-Layout ..."
    LAYOUT="$WORK_DIR/layout.json"
    # Positions match scripts/dmg/background.png (make-background.py).
    python3 - "$LAYOUT" "$APP_PATH" "$APP_NAME" "$SCRIPT_DIR/dmg/background.png" <<'EOF'
import json
import sys

layout, app, name, background = sys.argv[1:5]
with open(layout, "w") as file:
    json.dump({
        "title": name,
        "background": background,
        "icon-size": 112,
        "text-size": 13,
        "window": {"position": {"x": 200, "y": 140}, "size": {"width": 600, "height": 380}},
        "format": "UDZO",
        "contents": [
            {"x": 160, "y": 150, "type": "file", "path": app, "hide_extension": True},
            {"x": 440, "y": 150, "type": "link", "path": "/Applications", "name": "Programme"},
        ],
    }, file)
EOF
    python3 -m dmgbuild -s "$LAYOUT" "$APP_NAME" "$DMG_PATH"
else
    echo "ℹ️  dmgbuild fehlt (python3 -m pip install dmgbuild): DMG ohne Hintergrund und Anordnung."
    STAGING="$WORK_DIR/staging"
    mkdir -p "$STAGING"
    ditto "$APP_PATH" "$STAGING/$APP_NAME.app"
    ln -s /Applications "$STAGING/Programme"
    hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG_PATH"
fi

hdiutil verify "$DMG_PATH" >/dev/null
echo "✅ DMG fertig: $DMG_PATH ($(du -h "$DMG_PATH" | cut -f1))"

#!/bin/sh
# Build the release zip: plugin + source + overlay vpk + README, laid out like the L4D2 game folder (left4dead2/).
# Run build.sh and tools/make_bar.py --vpk first. The dev-only ge_lab plugin is never included.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
VERSION="$(sed -n 's/.*version = "\(.*\)".*/\1/p' "$HERE/scripting/grab_escape.sp")"
OUT="$HERE/release/grab_escape-$VERSION"
rm -rf "$OUT" "$OUT.zip"
mkdir -p "$OUT/left4dead2/addons/sourcemod/plugins" "$OUT/left4dead2/addons/sourcemod/scripting"
cp "$HERE/build/grab_escape.smx" "$OUT/left4dead2/addons/sourcemod/plugins/"
cp "$HERE/scripting/grab_escape.sp" "$OUT/left4dead2/addons/sourcemod/scripting/"
cp "$HERE/build/grab_escape.vpk" "$OUT/left4dead2/addons/"
cp "$HERE/README.md" "$HERE/LICENSE" "$OUT/"
(cd "$HERE/release" && powershell.exe -NoProfile -Command "Compress-Archive -Path 'grab_escape-$VERSION/*' -DestinationPath 'grab_escape-$VERSION.zip' -Force")
echo "built release/grab_escape-$VERSION.zip"

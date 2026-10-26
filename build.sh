#!/bin/sh
# Compile grab_escape.sp with SourceMod's own compiler (spcomp64; Smart App Control blocks spcomp.exe) and deploy it.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
SM="/c/Program Files (x86)/Steam/steamapps/common/Left 4 Dead 2/left4dead2/addons/sourcemod"
"$SM/scripting/spcomp64.exe" "$HERE/scripting/grab_escape.sp" -i"$SM/scripting/include" -o"$HERE/build/grab_escape.smx"
cp "$HERE/build/grab_escape.smx" "$SM/plugins/grab_escape.smx"
echo "deployed grab_escape.smx"

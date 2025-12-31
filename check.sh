#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Try to find lua-language-server
if command -v lua-language-server &> /dev/null; then
    LUA_LS="lua-language-server"
else
    # WSL: find from Windows VSCode extensions
    WIN_HOME=$(wslpath "$(cmd.exe /c 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r')" 2>/dev/null) || true
    if [ -n "$WIN_HOME" ]; then
        LUA_LS_EXE=$(find "$WIN_HOME/.vscode/extensions" -name "lua-language-server.exe" -path "*/sumneko.lua-*/server/bin/*" 2>/dev/null | head -1)
        if [ -n "$LUA_LS_EXE" ]; then
            WIN_PATH=$(wslpath -w "$LUA_LS_EXE")
            LUA_LS="cmd.exe /c $WIN_PATH"
        fi
    fi
fi

if [ -z "$LUA_LS" ]; then
    echo "lua-language-server not found"
    echo "Install via: apt install lua-language-server"
    echo "Or install sumneko.lua extension in VSCode"
    exit 1
fi

echo "Checking mane3d..."
$LUA_LS --check "$SCRIPT_DIR"

echo ""
echo "Done."

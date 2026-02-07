#!/usr/bin/env python3
"""Lua type-check and doc generation using lua-language-server."""

import argparse
import os
import platform
import shutil
import subprocess
import sys
from glob import glob
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent


def find_lua_ls() -> str | None:
    """Find lua-language-server binary.

    Search order:
      1. LUA_LS environment variable
      2. PATH
      3. VSCode sumneko.lua extension (Windows / WSL)
    """
    # 1. Environment variable
    env = os.environ.get("LUA_LS")
    if env and shutil.which(env):
        return env

    # 2. PATH
    path_bin = shutil.which("lua-language-server")
    if path_bin:
        return path_bin

    # 3. VSCode extension
    is_windows = platform.system() == "Windows"
    if is_windows:
        home = Path(os.environ.get("USERPROFILE", ""))
    else:
        # WSL: try Windows home
        try:
            result = subprocess.run(
                ["cmd.exe", "/c", "echo %USERPROFILE%"],
                capture_output=True, text=True, timeout=5,
            )
            win_home = result.stdout.strip()
            if win_home and "%" not in win_home:
                result2 = subprocess.run(
                    ["wslpath", win_home],
                    capture_output=True, text=True, timeout=5,
                )
                home = Path(result2.stdout.strip())
            else:
                home = Path.home()
        except (FileNotFoundError, subprocess.TimeoutExpired):
            home = Path.home()

    ext_dir = home / ".vscode" / "extensions"
    if ext_dir.is_dir():
        exe_name = "lua-language-server.exe" if is_windows else "lua-language-server"
        candidates = sorted(ext_dir.glob(f"sumneko.lua-*/server/bin/{exe_name}"))
        if candidates:
            return str(candidates[-1])  # latest version

    return None


def main() -> int:
    parser = argparse.ArgumentParser(description="Lua type-check with lua-language-server")
    parser.add_argument("--doc", action="store_true", help="Generate doc.json")
    args = parser.parse_args()

    lua_ls = find_lua_ls()
    if not lua_ls:
        print("lua-language-server not found")
        print("Set LUA_LS env var, install via package manager,")
        print("or install sumneko.lua extension in VSCode.")
        return 1

    print(f"Using: {lua_ls}")
    subprocess.run([lua_ls, "--version"], cwd=PROJECT_ROOT)

    # --check
    print("Checking lub3d...")
    result = subprocess.run(
        [lua_ls, "--configpath", ".luarc.json", "--check", "."],
        cwd=PROJECT_ROOT,
    )
    if result.returncode != 0:
        return result.returncode

    # --doc (optional)
    if args.doc:
        print("\nGenerating doc.json...")
        result = subprocess.run(
            [lua_ls, "--configpath", ".luarc-doc.json", "--doc", "."],
            cwd=PROJECT_ROOT,
        )
        if result.returncode != 0:
            return result.returncode

    print("\nDone.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

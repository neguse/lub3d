#!/usr/bin/env python3
"""Lua type-check and doc generation using lua-language-server."""

import argparse
import os
import platform
import re
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


_PASCAL_RE = re.compile(r"^[A-Z][a-zA-Z0-9]*[a-z][a-zA-Z0-9]*$")
_SNAKE_RE = re.compile(r"^_?[a-z][a-z0-9]*(_[a-z0-9]+)*_?$")
_ENUM_RE = re.compile(r"^_*[A-Z0-9][A-Za-z0-9]*(_[A-Za-z0-9]+)*_?$")
_CLASS_RE = re.compile(r"---@class\s+([\w.]+)")
_FIELD_RE = re.compile(r"---@field\s+(\w+)\??\s+(.*)")


def check_luacats_fields() -> int:
    """gen/*.lua の ---@field 命名規則チェック"""
    errors: list[str] = []
    gen_dir = PROJECT_ROOT / "gen"
    for lua_file in sorted(gen_dir.rglob("*.lua")):
        current_class: str | None = None
        for i, line in enumerate(lua_file.read_text(encoding="utf-8").splitlines(), 1):
            stripped = line.strip()

            cm = _CLASS_RE.match(stripped)
            if cm:
                current_class = cm.group(1)
                continue

            fm = _FIELD_RE.match(stripped)
            if not fm:
                if not stripped.startswith("---"):
                    current_class = None
                continue

            name, typ = fm.group(1), fm.group(2)
            typ_first = typ.split()[0] if typ else ""
            is_module = current_class is not None and current_class.endswith("_module")

            if "fun(" in typ and is_module:
                # module 関数: PascalCase (コンストラクタ) or snake_case
                if _PASCAL_RE.match(name) or _SNAKE_RE.match(name):
                    continue
            elif is_module and _PASCAL_RE.match(name):
                # module enum/型参照: PascalCase OK
                continue
            elif is_module and _ENUM_RE.match(name):
                # module 定数: UPPER_SNAKE_CASE OK
                continue
            elif "fun(" in typ:
                # struct メソッド/コールバック: snake_case
                if _SNAKE_RE.match(name):
                    continue
            elif current_class and typ_first == current_class:
                # enum 値: UPPER_SNAKE_CASE (数字始まり・trailing _ 等も許容)
                if _ENUM_RE.match(name):
                    continue
            else:
                # struct プロパティ: snake_case
                if _SNAKE_RE.match(name):
                    continue

            rel = lua_file.relative_to(PROJECT_ROOT)
            errors.append(f"  {rel}:{i}: field '{name}' (class: {current_class})")

    if errors:
        print(f"\nLuaCATS field check: {len(errors)} violation(s)")
        for e in errors:
            print(e)
        return 1

    print("LuaCATS field check: OK")
    return 0


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

    # LuaCATS field naming convention check
    rc = check_luacats_fields()
    if rc != 0:
        return rc

    print("\nDone.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

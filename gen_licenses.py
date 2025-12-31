#!/usr/bin/env python3
"""
Generate license data as C source from LICENSE files in deps/
"""
import os
import re
import json

# Override auto-detected values (only when necessary)
LIBRARY_INFO = {
    "glslang": {"type": "BSD-3-Clause/MIT/Apache-2.0"},  # Multi-license
    "tint-extract": {"name": "Tint"},  # Better display name
}

def detect_license_type(text):
    """Detect license type from text content."""
    text_lower = text.lower()

    if "apache license" in text_lower and "version 2.0" in text_lower:
        return "Apache-2.0"
    if "mit license" in text_lower or ("permission is hereby granted" in text_lower and "mit" in text_lower):
        return "MIT"
    if "permission is hereby granted, free of charge" in text_lower:
        # Could be MIT-style
        if "the above copyright notice and this permission notice" in text_lower:
            return "MIT"
    if "zlib" in text_lower and "libpng" in text_lower:
        return "zlib"
    if "'as-is'" in text_lower and "permission is granted to anyone" in text_lower:
        return "zlib"
    if "redistribution and use in source and binary forms" in text_lower:
        if "3. neither the name" in text_lower or "3.  neither the name" in text_lower:
            return "BSD-3-Clause"
        return "BSD-2-Clause"
    if "gnu general public license" in text_lower:
        return "GPL-3.0"

    return "Unknown"

def escape_c_string(s):
    """Escape string for C string literal."""
    result = []
    for c in s:
        if c == '\\':
            result.append('\\\\')
        elif c == '"':
            result.append('\\"')
        elif c == '\n':
            result.append('\\n')
        elif c == '\r':
            result.append('')  # skip CR
        elif c == '\t':
            result.append('\\t')
        elif ord(c) < 32 or ord(c) > 126:
            result.append(f'\\x{ord(c):02x}')
        else:
            result.append(c)
    return ''.join(result)

def find_licenses(root_dir):
    """Find all LICENSE files and extract info."""
    licenses = []

    # Mane3D itself
    licenses.append({
        "name": "Mane3D",
        "type": "MIT",
        "url": "https://github.com/neguse/mane3d",
        "text": """MIT License

Copyright (c) 2024 neguse

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE."""
    })

    # Lua (no LICENSE file, but MIT)
    lua_readme = os.path.join(root_dir, "deps/lua/README.md")
    if os.path.exists(lua_readme):
        licenses.append({
            "name": "Lua",
            "type": "MIT",
            "url": "https://lua.org",
            "text": """Lua License

Lua is free software distributed under the terms of the MIT license.

Copyright (c) 1994-2024 Lua.org, PUC-Rio.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE."""
        })

    # Walk deps directory for LICENSE files
    deps_dir = os.path.join(root_dir, "deps")
    for dirpath, dirnames, filenames in os.walk(deps_dir):
        for filename in filenames:
            if filename.startswith("LICENSE"):
                filepath = os.path.join(dirpath, filename)

                # Get relative path from deps
                rel_path = os.path.relpath(dirpath, deps_dir)
                parts = rel_path.split(os.sep)

                # Skip nested licenses (like vscode stuff)
                if "vscode" in rel_path.lower():
                    continue

                # Determine library name
                lib_key = parts[0] if parts else filename
                if len(parts) > 1 and parts[0] == "sokol-tools" and parts[1] == "ext":
                    lib_key = parts[2] if len(parts) > 2 else parts[1]

                # Get library info (use directory name as default)
                info = LIBRARY_INFO.get(lib_key, {})
                lib_name = info.get("name", lib_key)
                lib_url = info.get("url", "")

                # Read license text
                try:
                    with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
                        text = f.read()
                except:
                    continue

                # Skip if already added (by name)
                if any(l["name"] == lib_name for l in licenses):
                    continue

                # Use override type if specified, otherwise auto-detect
                license_type = info.get("type") or detect_license_type(text)

                licenses.append({
                    "name": lib_name,
                    "type": license_type,
                    "url": lib_url,
                    "text": text.strip()
                })

    return licenses

def split_string_literal(s, max_len=8000):
    """Split a long string into chunks for C string concatenation."""
    chunks = []
    while len(s) > max_len:
        # Find a good split point (after \n if possible)
        split_at = max_len
        for i in range(max_len, max(0, max_len - 200), -1):
            if i < len(s) and s[i:i+2] == '\\n':
                split_at = i + 2
                break
        chunks.append(s[:split_at])
        s = s[split_at:]
    chunks.append(s)
    return chunks

def generate_c_source(licenses, output_path):
    """Generate C source file with license data."""

    lines = [
        "/* Auto-generated by gen_licenses.py - do not edit */",
        "#include <lua.h>",
        "#include <lauxlib.h>",
        "",
        "typedef struct {",
        "    const char* name;",
        "    const char* type;",
        "    const char* url;",
        "    const char* text;",
        "} mane3d_license_t;",
        "",
        "static const mane3d_license_t mane3d_licenses[] = {",
    ]

    for lib in licenses:
        name = escape_c_string(lib["name"])
        ltype = escape_c_string(lib["type"])
        url = escape_c_string(lib["url"])
        text = escape_c_string(lib["text"])

        # Split long text into multiple string literals (MSVC limit ~16KB)
        text_chunks = split_string_literal(text)
        if len(text_chunks) == 1:
            lines.append(f'    {{"{name}", "{ltype}", "{url}", "{text}"}},')
        else:
            text_literal = '\n        "' + '"\n        "'.join(text_chunks) + '"'
            lines.append(f'    {{"{name}", "{ltype}", "{url}",{text_literal}}},')

    lines.append("};")
    lines.append("")
    lines.append(f"static const int mane3d_licenses_count = {len(licenses)};")
    lines.append("")

    # Lua binding
    lines.extend([
        "static int l_licenses_get(lua_State* L) {",
        "    lua_newtable(L);",
        "    for (int i = 0; i < mane3d_licenses_count; i++) {",
        "        lua_newtable(L);",
        "        lua_pushstring(L, mane3d_licenses[i].name);",
        "        lua_setfield(L, -2, \"name\");",
        "        lua_pushstring(L, mane3d_licenses[i].type);",
        "        lua_setfield(L, -2, \"type\");",
        "        lua_pushstring(L, mane3d_licenses[i].url);",
        "        lua_setfield(L, -2, \"url\");",
        "        lua_pushstring(L, mane3d_licenses[i].text);",
        "        lua_setfield(L, -2, \"text\");",
        "        lua_rawseti(L, -2, i + 1);",
        "    }",
        "    return 1;",
        "}",
        "",
        "static int l_licenses_notice(lua_State* L) {",
        "    luaL_Buffer b;",
        "    luaL_buffinit(L, &b);",
        "    luaL_addstring(&b, \"This software uses the following libraries:\\n\\n\");",
        "    for (int i = 0; i < mane3d_licenses_count; i++) {",
        "        luaL_addstring(&b, mane3d_licenses[i].name);",
        "        luaL_addstring(&b, \" (\");",
        "        luaL_addstring(&b, mane3d_licenses[i].type);",
        "        luaL_addstring(&b, \")\\n\");",
        "    }",
        "    luaL_pushresult(&b);",
        "    return 1;",
        "}",
        "",
        "static const luaL_Reg licenses_funcs[] = {",
        "    {\"libraries\", l_licenses_get},",
        "    {\"notice\", l_licenses_notice},",
        "    {NULL, NULL}",
        "};",
        "",
        "int luaopen_mane3d_licenses(lua_State* L) {",
        "    luaL_newlib(L, licenses_funcs);",
        "    return 1;",
        "}",
    ])

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines))
        f.write('\n')

def main():
    import argparse
    parser = argparse.ArgumentParser(description='Generate license data')
    parser.add_argument('--root', default=os.path.dirname(__file__), help='Root directory')
    parser.add_argument('--output', default=None, help='Output C file')
    args = parser.parse_args()

    root = os.path.abspath(args.root)
    output = args.output or os.path.join(root, 'gen', 'licenses.c')

    print(f"Scanning {root}/deps for licenses...")
    licenses = find_licenses(root)

    print(f"Found {len(licenses)} libraries:")
    for lib in licenses:
        print(f"  {lib['name']} ({lib['type']})")

    print(f"Generating {output}...")
    generate_c_source(licenses, output)
    print("Done.")

if __name__ == '__main__':
    main()

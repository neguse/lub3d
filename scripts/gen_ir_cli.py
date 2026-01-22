#!/usr/bin/env python3
"""
JSON IR generation CLI tool.

Generate JSON IR from C/C++ header files.

Usage:
    python scripts/gen_ir_cli.py <header>... --prefix <prefix> --module <name> [-o output.json]

Examples:
    python scripts/gen_ir_cli.py deps/bc7enc_rdo/bc7enc.h --prefix bc7enc_ --module bc7enc
    python scripts/gen_ir_cli.py deps/imgui/imgui.h deps/imgui/imgui_internal.h --prefix Im --module imgui
"""

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent.resolve()
PROJECT_ROOT = SCRIPT_DIR.parent
VERBOSE = False


# --- IR Generation (based on sokol/bindgen/gen_ir.py) ---

def filter_types(s):
    """Replace _Bool with bool."""
    return s.replace('_Bool', 'bool')


def get_first_non_comment(items):
    """Get first item that is not a comment."""
    return next(i for i in items if i['kind'] != 'FullComment')


def strip_comments(items):
    """Remove comment items."""
    return [i for i in items if i['kind'] != 'FullComment']


def extract_comment(comment, source):
    """Extract comment text from source."""
    return source[comment['range']['begin']['offset']:comment['range']['end']['offset']+1].rstrip()


def is_api_decl(decl, prefix):
    """Check if declaration matches API prefix."""
    if 'name' in decl:
        return decl['name'].startswith(prefix)
    elif decl['kind'] == 'EnumDecl':
        # Anonymous enum - check if items start with prefix
        if 'inner' not in decl:
            return False
        first = get_first_non_comment(decl['inner'])
        return first['name'].lower().startswith(prefix.lower())
    return False


def is_dep_decl(decl, dep_prefixes):
    """Check if declaration matches any dependency prefix."""
    for prefix in dep_prefixes:
        if is_api_decl(decl, prefix):
            return True
    return False


def get_dep_prefix(decl, dep_prefixes):
    """Get the matching dependency prefix."""
    for prefix in dep_prefixes:
        if is_api_decl(decl, prefix):
            return prefix
    return None


def parse_struct(decl, source):
    """Parse a struct declaration."""
    outp = {
        'kind': 'struct',
        'name': decl['name'],
        'fields': [],
    }
    for item_decl in decl.get('inner', []):
        if item_decl['kind'] == 'FullComment':
            outp['comment'] = extract_comment(item_decl, source)
            continue
        if item_decl['kind'] != 'FieldDecl':
            raise ValueError(f"Structs must only contain simple fields ({decl['name']})")
        item = {}
        if 'name' in item_decl:
            item['name'] = item_decl['name']
        item['type'] = filter_types(item_decl['type']['qualType'])
        outp['fields'].append(item)
    return outp


def parse_enum(decl, source):
    """Parse an enum declaration."""
    if 'name' in decl:
        outp = {'kind': 'enum', 'name': decl['name']}
        needs_value = False
    else:
        outp = {'kind': 'consts'}
        needs_value = True
    outp['items'] = []

    for item_decl in decl.get('inner', []):
        if item_decl['kind'] == 'FullComment':
            outp['comment'] = extract_comment(item_decl, source)
            continue
        if item_decl['kind'] == 'EnumConstantDecl':
            item = {'name': item_decl['name']}
            if 'inner' in item_decl:
                exprs = strip_comments(item_decl['inner'])
                if len(exprs) > 0:
                    const_expr = exprs[0]
                    if const_expr['kind'] != 'ConstantExpr':
                        raise ValueError(f"Enum values must be ConstantExpr ({item_decl['name']})")
                    if const_expr['valueCategory'] not in ('rvalue', 'prvalue'):
                        raise ValueError(f"Enum value must be rvalue/prvalue ({item_decl['name']})")
                    const_expr_inner = strip_comments(const_expr['inner'])
                    if not ((len(const_expr_inner) == 1) and (const_expr_inner[0]['kind'] == 'IntegerLiteral')):
                        raise ValueError(f"Enum value must have exactly one IntegerLiteral ({item_decl['name']})")
                    item['value'] = const_expr_inner[0]['value']
            if needs_value and 'value' not in item:
                raise ValueError("anonymous enum items require an explicit value")
            outp['items'].append(item)
    return outp


def parse_func(decl, source):
    """Parse a function declaration."""
    outp = {
        'kind': 'func',
        'name': decl['name'],
        'type': filter_types(decl['type']['qualType']),
        'params': [],
    }
    if 'inner' in decl:
        for param in decl['inner']:
            kind = param['kind']
            if kind == 'FullComment':
                outp['comment'] = extract_comment(param, source)
            elif kind == 'ParmVarDecl':
                outp['params'].append({
                    'name': param.get('name', ''),
                    'type': filter_types(param['type']['qualType']),
                })
            elif VERBOSE:
                print(f"  >> note: {decl['name']}: skipping {kind}")
    return outp


def parse_decl(decl, source):
    """Parse a declaration based on its kind."""
    kind = decl['kind']
    if kind == 'RecordDecl':
        return parse_struct(decl, source)
    elif kind == 'EnumDecl':
        return parse_enum(decl, source)
    elif kind == 'FunctionDecl':
        return parse_func(decl, source)
    return None


def run_clang(source_path, include_paths, cpp_mode):
    """Run clang to generate AST dump."""
    cmd = ["clang"]
    if cpp_mode:
        cmd.extend(["-x", "c++"])
    cmd.extend(["-Xclang", "-ast-dump=json", "-c", str(source_path)])
    for inc in include_paths:
        cmd.extend(["-I", str(inc)])
    return subprocess.check_output(cmd)


# --- MSVC Environment Setup ---

def find_vcvarsall():
    """Find vcvarsall.bat using vswhere.exe."""
    vswhere_paths = [
        Path(os.environ.get("ProgramFiles(x86)", "")) / "Microsoft Visual Studio" / "Installer" / "vswhere.exe",
        Path(os.environ.get("ProgramFiles", "")) / "Microsoft Visual Studio" / "Installer" / "vswhere.exe",
    ]

    vswhere = None
    for p in vswhere_paths:
        if p.exists():
            vswhere = p
            break

    if not vswhere:
        return None

    try:
        result = subprocess.run(
            [str(vswhere), "-latest", "-property", "installationPath"],
            capture_output=True,
            text=True,
            check=True,
        )
        vs_path = Path(result.stdout.strip())
        vcvarsall = vs_path / "VC" / "Auxiliary" / "Build" / "vcvarsall.bat"
        if vcvarsall.exists():
            return vcvarsall
    except subprocess.CalledProcessError:
        pass

    return None


def get_vcvars_env(vcvarsall, arch="x64"):
    """Run vcvarsall.bat and return the resulting environment variables."""
    cmd = f'"{vcvarsall}" {arch} && set'
    result = subprocess.run(cmd, capture_output=True, text=True, shell=True)

    if result.returncode != 0:
        return None

    env = {}
    for line in result.stdout.splitlines():
        if "=" in line:
            key, _, value = line.partition("=")
            env[key] = value

    return env


def setup_msvc_env():
    """Setup MSVC environment on Windows."""
    if sys.platform != "win32":
        return True

    # Check if clang is already available
    try:
        subprocess.run(["clang", "--version"], capture_output=True, check=True)
        return True
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass

    vcvarsall = find_vcvarsall()
    if not vcvarsall:
        print("Warning: Could not find vcvarsall.bat", file=sys.stderr)
        return False

    print(f"Setting up MSVC environment from {vcvarsall}")
    env = get_vcvars_env(vcvarsall)
    if env:
        os.environ.update(env)
        return True

    print("Warning: Failed to setup MSVC environment", file=sys.stderr)
    return False


# --- Main Logic ---

def create_temp_source(headers, include_paths, cpp_mode, defines):
    """Create a temporary source file that includes all headers."""
    ext = ".cpp" if cpp_mode else ".c"
    fd, path = tempfile.mkstemp(suffix=ext)

    with os.fdopen(fd, "w") as f:
        # Write defines
        for define in defines:
            f.write(f"#define {define}\n")

        # Include standard headers for C mode
        if not cpp_mode:
            f.write("#include <stdbool.h>\n")
            f.write("#include <stdint.h>\n")
            f.write("#include <stddef.h>\n")

        for inc in include_paths:
            f.write(f"// -I {inc}\n")
        for header in headers:
            header_path = Path(header).resolve()
            try:
                rel_path = header_path.relative_to(PROJECT_ROOT)
                f.write(f'#include "{rel_path}"\n')
            except ValueError:
                f.write(f'#include "{header_path}"\n')

    return path


def generate_ir(header_path, source_path, module, prefix, dep_prefixes, output_path, include_paths, cpp_mode):
    """Generate IR from header file."""
    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    # Run clang
    ast = run_clang(source_path, include_paths, cpp_mode)
    inp = json.loads(ast)

    # Build output
    outp = {
        'module': module,
        'prefix': prefix,
        'dep_prefixes': dep_prefixes or [],
        'decls': [],
    }

    with open(str(header_path), mode='r', newline='', encoding='utf-8') as f:
        source = f.read()

        # Optional first comment extraction (sokol-style)
        match = re.search(r"/\*(.*?)\*/", source, re.S)
        if match and "Project URL" in match.group(1):
            outp['comment'] = match.group(1)

        for decl in inp.get('inner', []):
            is_dep = is_dep_decl(decl, dep_prefixes or [])
            if is_api_decl(decl, prefix) or is_dep:
                # Skip forward declarations
                if decl['kind'] == 'RecordDecl' and 'inner' not in decl:
                    continue
                if decl['kind'] == 'EnumDecl' and 'inner' not in decl:
                    continue

                try:
                    outp_decl = parse_decl(decl, source)
                except (ValueError, KeyError, TypeError) as e:
                    name = decl.get('name', '<anonymous>')
                    print(f"  >> warning: skipping {decl['kind']} {name}: {e}")
                    continue

                if outp_decl is not None:
                    outp_decl['is_dep'] = is_dep
                    outp_decl['dep_prefix'] = get_dep_prefix(decl, dep_prefixes or [])
                    outp['decls'].append(outp_decl)

    with open(output_path, 'w') as f:
        f.write(json.dumps(outp, indent=2))

    print(f"Generated: {output_path}")
    return True


def main():
    parser = argparse.ArgumentParser(
        description="Generate JSON IR from C/C++ header files",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )

    parser.add_argument("headers", nargs="+", help="Header files to process")
    parser.add_argument("--prefix", required=True, help="Symbol prefix to filter (e.g., 'sg_', 'bc7enc_')")
    parser.add_argument("--module", required=True, help="Module name for output")
    parser.add_argument("-o", "--output", help="Output file path (default: gen/stubs/<module>.json)")
    parser.add_argument("-I", "--include", action="append", default=[], dest="include_paths",
                        help="Additional include paths (can be specified multiple times)")
    parser.add_argument("--dep-prefix", action="append", default=[], dest="dep_prefixes",
                        help="Dependency prefixes (can be specified multiple times)")
    parser.add_argument("--cpp", action="store_true", help="Parse as C++ instead of C")
    parser.add_argument("-D", "--define", action="append", default=[], dest="defines",
                        help="Preprocessor defines (can be specified multiple times)")
    parser.add_argument("-v", "--verbose", action="store_true",
                        help="Verbose output")

    args = parser.parse_args()

    global VERBOSE
    VERBOSE = args.verbose

    # Setup MSVC environment on Windows
    if not setup_msvc_env():
        print("Warning: Proceeding without MSVC environment setup", file=sys.stderr)

    # Resolve header paths
    headers = []
    for h in args.headers:
        header_path = Path(h)
        if not header_path.is_absolute():
            header_path = PROJECT_ROOT / header_path
        if not header_path.exists():
            print(f"Error: Header file not found: {h}", file=sys.stderr)
            return 1
        headers.append(header_path)

    # Resolve include paths
    include_paths = [PROJECT_ROOT]
    for inc in args.include_paths:
        inc_path = Path(inc)
        if not inc_path.is_absolute():
            inc_path = PROJECT_ROOT / inc_path
        include_paths.append(inc_path)

    # Default output path
    output_path = args.output
    if not output_path:
        output_path = PROJECT_ROOT / "gen" / "stubs" / f"{args.module}.json"
    else:
        output_path = Path(output_path)
        if not output_path.is_absolute():
            output_path = PROJECT_ROOT / output_path

    # Create temporary source file
    temp_source = create_temp_source(headers, include_paths, args.cpp, args.defines)

    try:
        success = generate_ir(
            header_path=headers[0],
            source_path=temp_source,
            module=args.module,
            prefix=args.prefix,
            dep_prefixes=args.dep_prefixes,
            output_path=output_path,
            include_paths=include_paths,
            cpp_mode=args.cpp,
        )
        return 0 if success else 1

    finally:
        try:
            os.unlink(temp_source)
        except OSError:
            pass


if __name__ == "__main__":
    sys.exit(main())

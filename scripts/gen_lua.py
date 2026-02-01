#!/usr/bin/env python3
"""
gen_lua.py - Lua binding generator entry point

Generates Lua bindings for all configured libraries.

Usage:
    python scripts/gen_lua.py [--bindgen PATH] [--sokol PATH]
"""

import argparse
import os
import sys

# Get paths
script_dir = os.path.dirname(os.path.abspath(__file__))
root_dir = os.path.abspath(os.path.join(script_dir, '..'))

# Parse arguments
parser = argparse.ArgumentParser(description='Generate Lua bindings')
parser.add_argument('--bindgen', default=os.path.join(root_dir, 'deps/sokol/bindgen'),
                    help='Path to sokol/bindgen directory')
parser.add_argument('--sokol', default=os.path.join(root_dir, 'deps/sokol'),
                    help='Path to sokol directory (for headers)')
args = parser.parse_args()

# Add CLANGPP directory to PATH for gen_ir.py
clangpp = os.environ.get('CLANGPP')
if clangpp:
    clang_dir = os.path.dirname(clangpp)
    os.environ['PATH'] = clang_dir + os.pathsep + os.environ.get('PATH', '')

# Add scripts directory to path
sys.path.insert(0, script_dir)

from binding_gen import Generator
from bindings import sokol


def generate_sokol():
    """Generate Sokol bindings"""
    gen = Generator(
        sokol_root=args.sokol,
        output_root=root_dir,
        bindgen_path=args.bindgen,
    )

    # Apply Sokol-specific configuration
    sokol.configure(gen)

    # Generate all modules
    gen.generate_all()


def main():
    # Generate all bindings
    generate_sokol()

    # Future: add more generators here
    # generate_imgui()
    # generate_jolt()


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""
Generate JSON IR for all libraries in deps/.

Usage:
    python scripts/gen_all_ir.py [-j N]  # N parallel jobs (default: CPU count)
"""

import argparse
import json
import os
import subprocess
import sys
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent.resolve()
PROJECT_ROOT = SCRIPT_DIR.parent
GEN_IR_CLI = SCRIPT_DIR / "gen_ir_cli.py"
LIBRARIES_JSON = SCRIPT_DIR / "libraries.json"


def load_libraries():
    """Load library definitions from libraries.json."""
    with open(LIBRARIES_JSON, "r", encoding="utf-8") as f:
        return json.load(f)


def run_gen_ir(args):
    """Run gen_ir_cli.py for a single library. Returns (module, success, output)."""
    lib = args
    cmd = [
        sys.executable,
        str(GEN_IR_CLI),
        *lib["headers"],
        "--prefix", lib["prefix"],
        "--module", lib["module"],
        *lib.get("options", []),
    ]

    result = subprocess.run(cmd, cwd=PROJECT_ROOT, capture_output=True, text=True)
    output = result.stdout + result.stderr
    return lib["module"], result.returncode == 0, output


def main():
    parser = argparse.ArgumentParser(description="Generate JSON IR for all libraries in deps/")
    parser.add_argument("-j", "--jobs", type=int, default=os.cpu_count(),
                        help=f"Number of parallel jobs (default: {os.cpu_count()})")
    args = parser.parse_args()

    libraries = load_libraries()

    # Filter libraries with existing headers
    tasks = []
    for lib in libraries:
        missing = [h for h in lib["headers"] if not (PROJECT_ROOT / h).exists()]
        if missing:
            print(f"Skipping {lib['module']}: missing headers {missing}")
            continue
        tasks.append(lib)

    print(f"Generating {len(tasks)} modules with {args.jobs} parallel jobs...")

    success_count = 0
    fail_count = 0
    failed = []

    with ProcessPoolExecutor(max_workers=args.jobs) as executor:
        futures = {executor.submit(run_gen_ir, task): task["module"] for task in tasks}

        for future in as_completed(futures):
            module, success, output = future.result()
            if success:
                success_count += 1
                print(f"  [OK] {module}")
            else:
                fail_count += 1
                failed.append(module)
                print(f"  [FAIL] {module}")
            # Print warnings/errors if any
            for line in output.splitlines():
                if "warning:" in line or "error:" in line or "Error:" in line:
                    print(f"       {line.strip()}")

    print(f"\nResults: {success_count} succeeded, {fail_count} failed")
    if failed:
        print(f"Failed: {', '.join(failed)}")

    return 0 if fail_count == 0 else 1


if __name__ == "__main__":
    sys.exit(main())

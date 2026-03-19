#!/usr/bin/env python3
from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def run(cmd: list[str]) -> int:
    print(f"[run_all_checks] Running: {' '.join(cmd)}")
    result = subprocess.run(cmd, cwd=ROOT)
    return result.returncode

def main() -> int:
    code = run([sys.executable, str(ROOT / "scripts" / "check_scaffold.py")])
    if code != 0:
        return code

    code = run(
        [
            sys.executable,
            "-m",
            "unittest",
            "discover",
            "-s",
            str(ROOT / "scripts" / "tests"),
            "-p",
            "test_*.py",
            "-v",
        ]
    )
    if code != 0:
        return code

    cargo = shutil.which("cargo")
    if cargo:
        code = run([cargo, "test", "--manifest-path", str(ROOT / "rust" / "Cargo.toml")])
        if code != 0:
            return code
    else:
        print("[run_all_checks] cargo not found; skipping Rust tests.")

    code = run([sys.executable, str(ROOT / "scripts" / "repo_audit.py"), "--strict"])
    if code != 0:
        return code

    print("[run_all_checks] Done.")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())

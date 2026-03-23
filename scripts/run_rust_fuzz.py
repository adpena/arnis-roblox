#!/usr/bin/env python3
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_FUZZ_DIR = ROOT / "rust" / "fuzz"


def discover_targets(fuzz_dir: Path) -> list[str]:
    targets_dir = fuzz_dir / "fuzz_targets"
    if not targets_dir.is_dir():
        return []
    return sorted(path.stem for path in targets_dir.glob("*.rs"))


def check_config(fuzz_dir: Path) -> tuple[bool, list[str]]:
    failures: list[str] = []
    if not (fuzz_dir / "Cargo.toml").is_file():
        failures.append(f"missing fuzz manifest: {fuzz_dir / 'Cargo.toml'}")
    targets = discover_targets(fuzz_dir)
    if not targets:
        failures.append(f"no fuzz targets found under {fuzz_dir / 'fuzz_targets'}")
    return (not failures, failures)


def run(cmd: list[str], *, cwd: Path) -> int:
    print(f"[run_rust_fuzz] Running: {' '.join(cmd)}")
    result = subprocess.run(cmd, cwd=cwd)
    return result.returncode


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Validate or smoke-build Rust cargo-fuzz targets.")
    parser.add_argument("--fuzz-dir", type=Path, default=DEFAULT_FUZZ_DIR)
    parser.add_argument("--check-config", action="store_true")
    parser.add_argument("--smoke-build", action="store_true")
    args = parser.parse_args(argv)

    fuzz_dir = args.fuzz_dir.resolve()
    ok, failures = check_config(fuzz_dir)
    if not ok:
        for failure in failures:
            print(f"[run_rust_fuzz] {failure}")
        return 1

    targets = discover_targets(fuzz_dir)
    print(f"[run_rust_fuzz] discovered targets: {', '.join(targets)}")

    if not args.smoke_build:
        return 0

    cargo = shutil.which("cargo")
    if cargo is None:
        print("[run_rust_fuzz] cargo is required for fuzz smoke builds.")
        return 1

    for target in targets:
        code = run([cargo, "+nightly", "fuzz", "build", target], cwd=fuzz_dir)
        if code != 0:
            return code

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

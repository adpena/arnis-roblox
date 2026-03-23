#!/usr/bin/env python3
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUST_MANIFEST = ROOT / "rust" / "Cargo.toml"
ROBLOX_SRC = ROOT / "roblox" / "src"
SELENE_CONFIG = ROOT / "roblox" / "selene.toml"
STYLUA_CONFIG = ROOT / "roblox" / "stylua.toml"
LUAU_SOURCE_ROOTS = (
    ROBLOX_SRC / "ReplicatedStorage",
    ROBLOX_SRC / "ServerScriptService",
    ROBLOX_SRC / "StarterPlayer",
)
AUSTIN_FIDELITY_RUNNER = ROOT / "scripts" / "run_austin_fidelity.sh"


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run repo checks and optional Austin fidelity validation.")
    parser.add_argument(
        "--with-austin-fidelity",
        action="store_true",
        help="Also run the bounded Austin export + Studio fidelity lane.",
    )
    parser.add_argument(
        "--austin-fidelity-report-dir",
        default="",
        help="Stable report directory to pass to scripts/run_austin_fidelity.sh.",
    )
    return parser.parse_args(argv)

def run(cmd: list[str]) -> int:
    print(f"[run_all_checks] Running: {' '.join(cmd)}")
    result = subprocess.run(cmd, cwd=ROOT)
    return result.returncode

def main(argv: list[str] | None = None) -> int:
    args = parse_args([] if argv is None else argv)

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

    code = run([sys.executable, str(ROOT / "scripts" / "verify_generated_austin_assets.py")])
    if code != 0:
        return code

    code = run([sys.executable, str(ROOT / "scripts" / "manifest_quality_audit.py")])
    if code != 0:
        return code

    selene = shutil.which("selene")
    if selene:
        code = run([selene, "--config", str(SELENE_CONFIG), *[str(path) for path in LUAU_SOURCE_ROOTS]])
        if code != 0:
            return code
    else:
        print("[run_all_checks] selene not found; skipping Luau lint.")

    stylua = shutil.which("stylua")
    if stylua:
        code = run(
            [
                stylua,
                "--check",
                "--config-path",
                str(STYLUA_CONFIG),
                *[str(path) for path in LUAU_SOURCE_ROOTS],
            ]
        )
        if code != 0:
            return code
    else:
        print("[run_all_checks] stylua not found; skipping Luau format check.")

    cargo = shutil.which("cargo")
    if cargo:
        code = run([cargo, "test", "--locked", "--manifest-path", str(RUST_MANIFEST)])
        if code != 0:
            return code
        code = run([cargo, "fmt", "--manifest-path", str(RUST_MANIFEST), "--all", "--", "--check"])
        if code != 0:
            return code
        code = run(
            [
                cargo,
                "clippy",
                "--locked",
                "--manifest-path",
                str(RUST_MANIFEST),
                "--all-targets",
                "--all-features",
                "--",
                "-D",
                "warnings",
            ]
        )
        if code != 0:
            return code
        code = run([sys.executable, str(ROOT / "scripts" / "run_rust_fuzz.py"), "--check-config"])
        if code != 0:
            return code
    else:
        print("[run_all_checks] cargo not found; skipping Rust tests/lints and fuzz config check.")

    code = run([sys.executable, str(ROOT / "scripts" / "repo_audit.py"), "--strict"])
    if code != 0:
        return code

    if args.with_austin_fidelity:
        command = ["bash", str(AUSTIN_FIDELITY_RUNNER)]
        if args.austin_fidelity_report_dir:
            command.extend(["--report-dir", args.austin_fidelity_report_dir])
        code = run(command)
        if code != 0:
            print(f"[run_all_checks] Austin fidelity lane failed in report-only mode (exit={code}).")

    print("[run_all_checks] Done.")
    return 0

if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

#!/usr/bin/env python3
from __future__ import annotations

import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HOOKS_SOURCE = ROOT / ".githooks"


def main() -> int:
    subprocess.run(
        ["git", "config", "core.hooksPath", str(HOOKS_SOURCE)],
        cwd=ROOT,
        check=True,
    )
    print(f"[install_git_hooks] core.hooksPath -> {HOOKS_SOURCE}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
from typing import Sequence


ROOT = Path(__file__).resolve().parents[1]
ROBLOX_DIR = ROOT / "roblox"
DEFAULT_OUTPUT_PLACE = ROBLOX_DIR / "out" / "arnis-test-clean.rbxlx"
DEFAULT_PROJECT_NAME = "default.project.json"
DEFAULT_STUDIO_APP = Path("/Applications/RobloxStudio.app")


def resolve_vsync_binary() -> str:
    configured_binary = os.environ.get("VSYNC_BIN")
    if configured_binary and os.access(configured_binary, os.X_OK):
        return configured_binary

    repo_dir = Path(
        os.environ.get("VSYNC_REPO_DIR", str(ROOT.parent / "vertigo-sync"))
    )
    repo_binary = repo_dir / "target" / "debug" / "vsync"
    if repo_binary.is_file() and os.access(repo_binary, os.X_OK):
        return str(repo_binary)

    cargo_binary = Path.home() / ".cargo" / "bin" / "vsync"
    if cargo_binary.is_file() and os.access(cargo_binary, os.X_OK):
        return str(cargo_binary)

    discovered_binary = shutil.which("vsync")
    if discovered_binary:
        return discovered_binary

    raise FileNotFoundError(
        "could not find a `vsync` binary; set VSYNC_BIN or install/build vertigo-sync first"
    )


def build_place(
    vsync_binary: str,
    roblox_dir: Path,
    output_path: Path,
    *,
    project_name: str = DEFAULT_PROJECT_NAME,
    run_command=subprocess.run,
) -> Path:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    run_command(
        [
            vsync_binary,
            "--root",
            str(roblox_dir),
            "build",
            "--project",
            project_name,
            "--output",
            str(output_path),
        ],
        check=True,
    )
    return output_path


def build_serve_command(vsync_binary: str, *, project_name: str = DEFAULT_PROJECT_NAME) -> list[str]:
    return [
        vsync_binary,
        "serve",
        "--project",
        project_name,
    ]


def open_place_in_studio(
    place_path: Path,
    *,
    studio_app: Path = DEFAULT_STUDIO_APP,
    run_command=subprocess.run,
) -> None:
    if sys.platform == "darwin":
        if studio_app.exists():
            run_command(["open", "-a", str(studio_app), str(place_path)], check=True)
        else:
            run_command(["open", str(place_path)], check=True)
        return

    opener = shutil.which("xdg-open")
    if opener:
        run_command([opener, str(place_path)], check=True)
        return

    raise RuntimeError(
        f"automatic Studio open is not supported on this platform; open {place_path} manually"
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Build a clean Arnis Studio place from roblox/default.project.json and "
            "optionally open it in Roblox Studio."
        )
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT_PLACE,
        help=f"Output place path. Default: {DEFAULT_OUTPUT_PLACE}",
    )
    parser.add_argument(
        "--serve",
        action="store_true",
        help="Start `vsync serve --project default.project.json` before building the place.",
    )
    parser.add_argument(
        "--open",
        action="store_true",
        help="Open the built place in Roblox Studio after the build succeeds.",
    )
    parser.add_argument(
        "--roblox-root",
        type=Path,
        default=ROBLOX_DIR,
        help=f"Roblox project root to build from. Default: {ROBLOX_DIR}",
    )
    parser.add_argument(
        "--project-name",
        type=str,
        default=DEFAULT_PROJECT_NAME,
        help=f"Project file name relative to --roblox-root. Default: {DEFAULT_PROJECT_NAME}",
    )
    parser.add_argument(
        "--vsync-bin",
        type=str,
        default=None,
        help="Explicit vsync binary to use. Default: auto-detect from VSYNC_BIN, adjacent vertigo-sync, cargo bin, or PATH.",
    )
    parser.add_argument(
        "--studio-app",
        type=Path,
        default=DEFAULT_STUDIO_APP,
        help=f"Roblox Studio app path for --open on macOS. Default: {DEFAULT_STUDIO_APP}",
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    try:
        vsync_binary = args.vsync_bin or resolve_vsync_binary()
        if args.serve:
            subprocess.Popen(
                build_serve_command(vsync_binary, project_name=args.project_name),
                cwd=args.roblox_root.resolve(),
            )
        output_path = build_place(
            vsync_binary,
            args.roblox_root.resolve(),
            args.output.resolve(),
            project_name=args.project_name,
        )
    except (FileNotFoundError, subprocess.CalledProcessError) as exc:
        print(f"[bootstrap] {exc}", file=sys.stderr)
        return 1

    print(f"Built clean Arnis place: {output_path}")
    print(f"Project source: {args.roblox_root.resolve() / args.project_name}")
    if args.open:
        try:
            open_place_in_studio(output_path, studio_app=args.studio_app)
        except (RuntimeError, subprocess.CalledProcessError) as exc:
            print(f"[bootstrap] {exc}", file=sys.stderr)
            return 1
        print("Opened the bootstrap place in Roblox Studio.")
    else:
        print(f"Next: open {output_path} in Roblox Studio.")

    print(
        "For live sync after bootstrap, run `cd roblox && vsync serve --project default.project.json` "
        "and connect the generic Vertigo Sync plugin."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
from typing import NamedTuple

from bootstrap_arnis_studio import (
    DEFAULT_OUTPUT_PLACE,
    build_serve_command as build_serve_command_for_default_project,
    build_place,
    main as bootstrap_main,
    open_place_in_studio,
    resolve_vsync_binary,
)


class BootstrapPlan(NamedTuple):
    repo_root: Path
    roblox_root: Path
    project_path: Path
    output_place_path: Path
    next_steps: str


def resolve_repo_root(start: Path | None = None) -> Path:
    if start is None:
        start = Path(__file__).resolve().parents[1]
    return start.resolve()


def build_bootstrap_plan(repo_root: Path, open_studio: bool) -> BootstrapPlan:
    repo_root = repo_root.resolve()
    roblox_root = repo_root / "roblox"
    project_path = roblox_root / "default.project.json"
    output_place_path = roblox_root / "out" / DEFAULT_OUTPUT_PLACE.name
    next_steps_lines = [
        "1. Run the local sync server from roblox/: `vsync serve --project default.project.json`",
        f"2. Open `{output_place_path}` in Roblox Studio.",
        "3. Let the VertigoSync plugin connect to the local server and rebuild the preview/runtime state.",
    ]
    if open_studio:
        next_steps_lines.append("4. Studio will be opened automatically after the place is built.")
    return BootstrapPlan(
        repo_root=repo_root,
        roblox_root=roblox_root,
        project_path=project_path,
        output_place_path=output_place_path,
        next_steps="\n".join(next_steps_lines),
    )


def build_place_command(plan: BootstrapPlan, vsync_binary: str) -> list[str]:
    return [
        vsync_binary,
        "--root",
        str(plan.roblox_root),
        "build",
        "--project",
        plan.project_path.name,
        "--output",
        f"out/{plan.output_place_path.name}",
    ]


def build_serve_command(plan: BootstrapPlan, vsync_binary: str) -> list[str]:
    return build_serve_command_for_default_project(vsync_binary)


def run_build(plan: BootstrapPlan, vsync_binary: str) -> None:
    build_place(vsync_binary, plan.roblox_root, plan.output_place_path)


def open_studio_place(place_path: Path) -> None:
    open_place_in_studio(place_path)


def main(argv: list[str] | None = None) -> int:
    return bootstrap_main(argv)


if __name__ == "__main__":
    raise SystemExit(main())

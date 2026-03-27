#!/usr/bin/env python3
from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path


RUNTIME_SAMPLE_DATA_PATHS = {
    "src/ServerStorage/SampleData/AustinManifestIndex.lua",
    "src/ServerStorage/SampleData/AustinManifestChunks/**",
}
RUNTIME_HARNESS_SAMPLE_DATA_PATHS = {
    "src/ServerStorage/SampleData/AustinHarnessManifestIndex.lua",
    "src/ServerStorage/SampleData/AustinHarnessManifestChunks/**",
}
PREVIEW_FIXTURE_PATHS = {
    "src/ServerScriptService/StudioPreview/AustinPreviewManifestIndex.lua",
    "src/ServerScriptService/StudioPreview/AustinPreviewManifestChunks/**",
}
COMPILED_FIXTURE_PATHS = RUNTIME_SAMPLE_DATA_PATHS | RUNTIME_HARNESS_SAMPLE_DATA_PATHS | PREVIEW_FIXTURE_PATHS


def _load_project(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _build_build_project(default_project_data: dict, *, include_runtime_sample_data: bool) -> dict:
    build_data = copy.deepcopy(default_project_data)
    build_data.pop("vertigoSync", None)

    ignore_paths = set(build_data.get("globIgnorePaths", []))
    ignore_paths.update(COMPILED_FIXTURE_PATHS)

    build_visible_paths = set(PREVIEW_FIXTURE_PATHS)
    if include_runtime_sample_data:
        build_visible_paths.update(RUNTIME_HARNESS_SAMPLE_DATA_PATHS)

    for path in build_visible_paths:
        ignore_paths.discard(path)

    build_data["globIgnorePaths"] = sorted(ignore_paths)
    return build_data


def _build_serve_project(default_project_data: dict, *, enable_edit_preview: bool) -> dict:
    serve_data = copy.deepcopy(default_project_data)
    ignore_paths = set(serve_data.get("globIgnorePaths", []))
    ignore_paths.update(COMPILED_FIXTURE_PATHS)
    serve_data["globIgnorePaths"] = sorted(ignore_paths)
    if not enable_edit_preview:
        vertigo_sync = serve_data.get("vertigoSync")
        if isinstance(vertigo_sync, dict):
            vertigo_sync.pop("editPreview", None)
            if not vertigo_sync:
                serve_data.pop("vertigoSync", None)
    return serve_data


def generate_harness_projects(
    *,
    default_project: Path,
    build_project: Path,
    serve_project: Path,
    include_runtime_sample_data: bool,
) -> None:
    default_project_data = _load_project(default_project)
    build_data = _build_build_project(
        default_project_data,
        include_runtime_sample_data=include_runtime_sample_data,
    )
    serve_data = _build_serve_project(
        default_project_data,
        enable_edit_preview=not include_runtime_sample_data,
    )

    build_project.write_text(json.dumps(build_data, indent=2), encoding="utf-8")
    serve_project.write_text(json.dumps(serve_data, indent=2), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate harness-specific Roblox project files.")
    parser.add_argument("--default-project", type=Path, required=True)
    parser.add_argument("--build-project", type=Path, required=True)
    parser.add_argument("--serve-project", type=Path, required=True)
    parser.add_argument(
        "--include-runtime-sample-data",
        action="store_true",
        help="Include Austin runtime sample-data fixtures in the build project.",
    )
    args = parser.parse_args()

    generate_harness_projects(
        default_project=args.default_project,
        build_project=args.build_project,
        serve_project=args.serve_project,
        include_runtime_sample_data=args.include_runtime_sample_data,
    )


if __name__ == "__main__":
    main()

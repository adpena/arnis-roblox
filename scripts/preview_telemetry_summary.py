#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


def _as_bool_flag(value: Any) -> int:
    return 1 if bool(value) else 0


def summarize_plugin_state(data: dict[str, Any]) -> str:
    runtime = data.get("preview_runtime") or {}
    runtime_connection = runtime.get("connection") or {}
    project = data.get("preview_project") or {}
    project_preview = project.get("preview") or {}
    project_full_bake = project.get("full_bake") or {}
    project_snapshot = data.get("preview_project_snapshot") or {}
    project_counters = project_snapshot.get("counters") or {}
    project_chunks = project_snapshot.get("chunkTotals") or {}

    runtime_parts = [
        f"connected={_as_bool_flag(runtime.get('studio_connected'))}",
        f"attached={_as_bool_flag(runtime.get('plugin_attached'))}",
        f"project_loaded={_as_bool_flag(runtime.get('project_loaded'))}",
        f"sync_status={runtime.get('sync_status', 'unknown')}",
        f"ws_connected={_as_bool_flag(runtime_connection.get('ws_connected'))}",
    ]

    project_parts = [
        f"sync_state={project_preview.get('sync_state', 'unknown')}",
        f"build_active={_as_bool_flag(project_preview.get('build_active'))}",
        f"state_apply_pending={_as_bool_flag(project_preview.get('state_apply_pending'))}",
        f"full_bake_active={_as_bool_flag(project_full_bake.get('active'))}",
    ]

    if project_counters or project_chunks:
        project_parts.extend(
            [
                f"build={project_counters.get('build_scheduled', 0)}",
                f"sync_complete={project_counters.get('sync_complete', 0)}",
                f"sync_cancelled={project_counters.get('sync_cancelled', 0)}",
                f"state_apply_succeeded={project_counters.get('state_apply_succeeded', 0)}",
                f"state_apply_failed={project_counters.get('state_apply_failed', 0)}",
                f"imported={project_chunks.get('imported', 0)}",
                f"skipped={project_chunks.get('skipped', 0)}",
                f"unloaded={project_chunks.get('unloaded', 0)}",
            ]
        )
    else:
        full_bake_last_result = project_full_bake.get("last_result")
        if full_bake_last_result is not None:
            project_parts.append(f"full_bake_last_result={full_bake_last_result}")

    return f"runtime={' '.join(runtime_parts)}; project={' '.join(project_parts)}"


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Summarize Vertigo Sync preview telemetry from /plugin/state JSON."
    )
    parser.add_argument("plugin_state_json", type=Path)
    parser.add_argument("summary_out", type=Path)
    args = parser.parse_args()

    data = json.loads(args.plugin_state_json.read_text(encoding="utf-8"))
    summary = summarize_plugin_state(data)
    args.summary_out.write_text(summary, encoding="utf-8")
    print(summary)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

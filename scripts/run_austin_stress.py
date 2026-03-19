#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import statistics
import subprocess
import sys
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "scripts" / "run_studio_harness.sh"

PERF_RE = re.compile(
    r"\[RunAustin\] Perf summary: refs=(?P<refs>\d+) imported=(?P<imported>\d+) total=(?P<total>[0-9.]+)ms "
    r"hot=(?P<hot_label>\S+) (?P<hot_ms>[0-9.]+)ms slowest=(?P<slow_label>\S+) (?P<slow_ms>[0-9.]+)ms"
)
ANCHOR_RE = re.compile(
    r"\[RunAustin\] Austin anchor: focus=\((?P<fx>-?[0-9.]+), (?P<fy>-?[0-9.]+), (?P<fz>-?[0-9.]+)\) "
    r"spawn=\((?P<sx>-?[0-9.]+), (?P<sy>-?[0-9.]+), (?P<sz>-?[0-9.]+)\)"
)
PREVIEW_RE = re.compile(
    r"\[AustinPreviewBuilder\] sync complete .*? elapsedMs=(?P<elapsed>\d+).*? imported=(?P<imported>\d+).*?targetChunks=(?P<target>\d+)"
)


@dataclass(frozen=True)
class PerfSummary:
    refs: int
    imported: int
    total_ms: float
    hot_label: str
    hot_ms: float
    slow_label: str
    slow_ms: float


@dataclass(frozen=True)
class AnchorSummary:
    focus: dict[str, float]
    spawn: dict[str, float]


def parse_perf_summary(line: str) -> PerfSummary | None:
    match = PERF_RE.search(line)
    if match is None:
        return None
    return PerfSummary(
        refs=int(match.group("refs")),
        imported=int(match.group("imported")),
        total_ms=float(match.group("total")),
        hot_label=match.group("hot_label"),
        hot_ms=float(match.group("hot_ms")),
        slow_label=match.group("slow_label"),
        slow_ms=float(match.group("slow_ms")),
    )


def parse_anchor_line(line: str) -> AnchorSummary | None:
    match = ANCHOR_RE.search(line)
    if match is None:
        return None
    return AnchorSummary(
        focus={
            "x": float(match.group("fx")),
            "y": float(match.group("fy")),
            "z": float(match.group("fz")),
        },
        spawn={
            "x": float(match.group("sx")),
            "y": float(match.group("sy")),
            "z": float(match.group("sz")),
        },
    )


def parse_json_marker(prefix: str, line: str) -> dict[str, Any] | None:
    marker = prefix + " "
    if not line.startswith(marker):
        return None
    return json.loads(line[len(marker) :])


def parse_iteration(lines: list[str]) -> dict[str, Any]:
    result: dict[str, Any] = {
        "perf": None,
        "anchor": None,
        "preview": None,
        "edit": None,
        "play": None,
        "play_late": None,
        "lines": lines,
    }
    for line in lines:
        if result["perf"] is None:
            perf = parse_perf_summary(line)
            if perf is not None:
                result["perf"] = asdict(perf)
                continue
        if result["anchor"] is None:
            anchor = parse_anchor_line(line)
            if anchor is not None:
                result["anchor"] = asdict(anchor)
                continue
        if result["preview"] is None:
            preview_match = PREVIEW_RE.search(line)
            if preview_match is not None:
                result["preview"] = {
                    "elapsed_ms": int(preview_match.group("elapsed")),
                    "imported": int(preview_match.group("imported")),
                    "target_chunks": int(preview_match.group("target")),
                }
                continue
        if result["edit"] is None:
            payload = parse_json_marker("ARNIS_MCP_EDIT", line)
            if payload is not None:
                result["edit"] = payload
                continue
        if result["play"] is None:
            payload = parse_json_marker("ARNIS_MCP_PLAY", line)
            if payload is not None:
                result["play"] = payload
                continue
        if result["play_late"] is None:
            payload = parse_json_marker("ARNIS_MCP_PLAY_LATE", line)
            if payload is not None:
                result["play_late"] = payload
                continue
    return result


def evaluate_iteration(iteration: dict[str, Any]) -> list[str]:
    failures: list[str] = []
    if iteration["perf"] is None:
        failures.append("Perf summary missing")
    if iteration["anchor"] is None:
        failures.append("Runtime anchor missing")
    if not (iteration["edit"] or {}).get("generatedExists"):
        failures.append("Edit probe did not observe generated Austin preview")
    play = iteration["play"] or {}
    if not play.get("generatedExists"):
        failures.append("Play probe did not observe generated Austin world")
    if play.get("root") is None:
        failures.append("Play probe did not observe HumanoidRootPart")
    late = iteration["play_late"] or {}
    if late.get("loadingPad") is not None:
        failures.append("AustinLoadingPad still present late in play probe")
    return failures


def summarize_iterations(iterations: list[dict[str, Any]]) -> dict[str, Any]:
    perf_totals = [iteration["perf"]["total_ms"] for iteration in iterations if iteration["perf"]]
    preview_totals = [
        iteration["preview"]["elapsed_ms"] for iteration in iterations if iteration["preview"]
    ]
    failures = [
        {"iteration": index + 1, "failures": evaluate_iteration(iteration)}
        for index, iteration in enumerate(iterations)
        if evaluate_iteration(iteration)
    ]
    summary: dict[str, Any] = {
        "iterations": len(iterations),
        "failures": failures,
        "ok": len(failures) == 0,
    }
    if perf_totals:
        summary["runtime_import_ms"] = {
            "min": min(perf_totals),
            "max": max(perf_totals),
            "avg": statistics.fmean(perf_totals),
            "median": statistics.median(perf_totals),
        }
    if preview_totals:
        summary["preview_elapsed_ms"] = {
            "min": min(preview_totals),
            "max": max(preview_totals),
            "avg": statistics.fmean(preview_totals),
            "median": statistics.median(preview_totals),
        }
    return summary


def run_iteration(args: argparse.Namespace, iteration_index: int) -> dict[str, Any]:
    cmd = [
        "bash",
        str(HARNESS),
        "--takeover",
        "--hard-restart",
        "--edit-wait",
        str(args.edit_wait),
        "--play-wait",
        str(args.play_wait),
        "--pattern-wait",
        str(args.pattern_wait),
    ]
    if args.keep_open:
        cmd.append("--keep-open")
    if args.no_play:
        cmd.append("--no-play")

    print(f"[run_austin_stress] iteration={iteration_index + 1} cmd={' '.join(cmd)}")
    process = subprocess.Popen(
        cmd,
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    assert process.stdout is not None
    lines: list[str] = []
    for raw_line in process.stdout:
        line = raw_line.rstrip("\n")
        print(line)
        lines.append(line)
    exit_code = process.wait()
    if exit_code != 0:
        raise RuntimeError(f"harness iteration {iteration_index + 1} failed with exit code {exit_code}")
    return parse_iteration(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Run repeated Austin harness stress iterations.")
    parser.add_argument("--iterations", type=int, default=3)
    parser.add_argument("--edit-wait", type=int, default=20)
    parser.add_argument("--play-wait", type=int, default=25)
    parser.add_argument("--pattern-wait", type=int, default=120)
    parser.add_argument("--json-out", type=Path)
    parser.add_argument("--keep-open", action="store_true")
    parser.add_argument("--no-play", action="store_true")
    args = parser.parse_args(argv)

    iterations = [run_iteration(args, index) for index in range(args.iterations)]
    summary = summarize_iterations(iterations)
    payload = {"summary": summary, "iterations": iterations}

    if args.json_out is not None:
        args.json_out.write_text(json.dumps(payload, indent=2), encoding="utf-8")

    print(json.dumps(summary, indent=2))
    return 0 if summary["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())

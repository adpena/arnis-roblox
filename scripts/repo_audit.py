#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]

DEFAULT_WARN_LIMIT_BYTES = 50 * 1024 * 1024
DEFAULT_HARD_LIMIT_BYTES = 100 * 1024 * 1024
REQUIRED_IGNORE_RULES = [
    "rust/out/",
    "roblox/out/",
    "out/",
    "tmp/",
    "roblox/src/ServerStorage/SampleData/AustinManifest.lua",
    ".env",
    ".env.*",
    "*.pem",
    "*.key",
    "*.log",
]


@dataclass(frozen=True)
class BlobFinding:
    path: str
    size_bytes: int


@dataclass(frozen=True)
class SecretFinding:
    rule_id: str
    description: str
    path: str
    start_line: int


@dataclass(frozen=True)
class PushReadiness:
    ok: bool
    failures: list[str]
    warnings: list[str]


def run(
    cmd: list[str],
    *,
    check: bool = True,
    capture_output: bool = True,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    merged_env = os.environ.copy()
    if env:
        merged_env.update(env)
    return subprocess.run(
        cmd,
        cwd=ROOT,
        env=merged_env,
        text=True,
        capture_output=capture_output,
        check=check,
    )


def format_bytes(size_bytes: int) -> str:
    units = ["B", "KB", "MB", "GB"]
    value = float(size_bytes)
    for unit in units:
        if value < 1024 or unit == units[-1]:
            return f"{value:.1f}{unit}"
        value /= 1024
    return f"{size_bytes}B"


def parse_large_blob_rows(output: str) -> list[BlobFinding]:
    blobs: list[BlobFinding] = []
    for raw_line in output.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        size, path = line.split("\t", 1)
        blobs.append(BlobFinding(path=path, size_bytes=int(size)))
    return blobs


def find_large_reachable_blobs(min_size_bytes: int) -> list[BlobFinding]:
    rev_list = subprocess.Popen(
        ["git", "rev-list", "--objects", "--all"],
        cwd=ROOT,
        stdout=subprocess.PIPE,
        text=True,
    )
    assert rev_list.stdout is not None
    cat_file = subprocess.run(
        [
            "git",
            "cat-file",
            "--batch-check=%(objecttype) %(objectname) %(objectsize) %(rest)",
        ],
        cwd=ROOT,
        stdin=rev_list.stdout,
        text=True,
        capture_output=True,
        check=True,
    )
    rev_list.stdout.close()
    rev_list.wait()

    rows: list[str] = []
    for line in cat_file.stdout.splitlines():
        parts = line.split(" ", 3)
        if len(parts) != 4:
            continue
        object_type, _object_id, object_size, path = parts
        if object_type != "blob":
            continue
        size = int(object_size)
        if size >= min_size_bytes:
            rows.append(f"{size}\t{path}")
    rows.sort(key=lambda row: int(row.split("\t", 1)[0]), reverse=True)
    return parse_large_blob_rows("\n".join(rows))


def load_gitignore() -> str:
    return (ROOT / ".gitignore").read_text()


def find_missing_ignore_rules(gitignore_text: str, required_rules: list[str]) -> list[str]:
    lines = {line.strip() for line in gitignore_text.splitlines()}
    return [rule for rule in required_rules if rule not in lines]


def find_tracked_ignored_files() -> list[str]:
    result = run(
        ["git", "ls-files", "-ci", "--exclude-standard"],
        check=False,
    )
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def find_staged_deletions() -> set[str]:
    result = run(
        ["git", "diff", "--cached", "--name-only", "--diff-filter=D"],
        check=False,
    )
    return {line.strip() for line in result.stdout.splitlines() if line.strip()}


def exclude_staged_deletions(
    *,
    tracked_ignored: list[str],
    staged_deletions: set[str],
) -> list[str]:
    return [path for path in tracked_ignored if path not in staged_deletions]


def load_gitleaks_report(report_path: Path) -> list[SecretFinding]:
    if not report_path.exists() or not report_path.read_text().strip():
        return []
    findings_raw = json.loads(report_path.read_text())
    findings: list[SecretFinding] = []
    for row in findings_raw:
        findings.append(
            SecretFinding(
                rule_id=row.get("RuleID", ""),
                description=row.get("Description", ""),
                path=row.get("File", ""),
                start_line=int(row.get("StartLine", 0) or 0),
            )
        )
    return findings


def run_gitleaks() -> list[SecretFinding]:
    if shutil.which("gitleaks") is None:
        return []

    with tempfile.TemporaryDirectory() as tmp_dir:
        report_path = Path(tmp_dir) / "gitleaks.json"
        result = run(
            [
                "gitleaks",
                "git",
                str(ROOT),
                "--report-format",
                "json",
                "--report-path",
                str(report_path),
                "--redact",
                "--no-banner",
                "--exit-code",
                "0",
                "--timeout",
                "120",
                "--max-target-megabytes",
                "10",
                "--log-opts=--all",
            ],
            check=False,
        )
        if result.returncode not in (0, 1):
            raise RuntimeError(result.stderr.strip() or "gitleaks failed")
        return load_gitleaks_report(report_path)


def run_git_sizer() -> dict[str, Any] | None:
    if shutil.which("git-sizer") is None:
        return None
    result = run(["git-sizer", "--json", "--json-version=1"])
    return json.loads(result.stdout)


def evaluate_push_readiness(
    *,
    hard_limit_bytes: int,
    warn_limit_bytes: int,
    large_blobs: list[BlobFinding],
    secret_findings: list[SecretFinding],
    tracked_ignored: list[str],
    missing_ignore_rules: list[str],
) -> PushReadiness:
    failures: list[str] = []
    warnings: list[str] = []

    hard_fail_blobs = [blob for blob in large_blobs if blob.size_bytes >= hard_limit_bytes]
    warn_blobs = [
        blob
        for blob in large_blobs
        if warn_limit_bytes <= blob.size_bytes < hard_limit_bytes
    ]

    if hard_fail_blobs:
        failures.append(
            "Large reachable blobs exceed hard limit: "
            + ", ".join(f"{blob.path} ({format_bytes(blob.size_bytes)})" for blob in hard_fail_blobs)
        )
    if warn_blobs:
        warnings.append(
            "Large reachable blobs exceed warning limit: "
            + ", ".join(f"{blob.path} ({format_bytes(blob.size_bytes)})" for blob in warn_blobs)
        )
    if secret_findings:
        failures.append(
            "Secret findings detected in reachable history: "
            + ", ".join(
                f"{finding.rule_id}:{finding.path}:{finding.start_line}"
                for finding in secret_findings[:10]
            )
        )
    if tracked_ignored:
        failures.append(
            "Tracked files match ignore rules: " + ", ".join(tracked_ignored[:20])
        )
    if missing_ignore_rules:
        failures.append(
            "Missing required ignore rules: " + ", ".join(missing_ignore_rules)
        )

    return PushReadiness(ok=not failures, failures=failures, warnings=warnings)


def build_summary(
    *,
    warn_limit_bytes: int,
    hard_limit_bytes: int,
    include_gitleaks: bool,
    include_git_sizer: bool,
) -> dict[str, Any]:
    large_blobs = find_large_reachable_blobs(warn_limit_bytes)
    missing_ignore_rules = find_missing_ignore_rules(load_gitignore(), REQUIRED_IGNORE_RULES)
    tracked_ignored = exclude_staged_deletions(
        tracked_ignored=find_tracked_ignored_files(),
        staged_deletions=find_staged_deletions(),
    )
    secret_findings = run_gitleaks() if include_gitleaks else []
    git_sizer = run_git_sizer() if include_git_sizer else None
    readiness = evaluate_push_readiness(
        hard_limit_bytes=hard_limit_bytes,
        warn_limit_bytes=warn_limit_bytes,
        large_blobs=large_blobs,
        secret_findings=secret_findings,
        tracked_ignored=tracked_ignored,
        missing_ignore_rules=missing_ignore_rules,
    )
    return {
        "ok": readiness.ok,
        "limits": {
            "warn_bytes": warn_limit_bytes,
            "hard_bytes": hard_limit_bytes,
        },
        "large_blobs": [asdict(blob) for blob in large_blobs],
        "secret_findings": [asdict(finding) for finding in secret_findings],
        "tracked_ignored": tracked_ignored,
        "missing_ignore_rules": missing_ignore_rules,
        "warnings": readiness.warnings,
        "failures": readiness.failures,
        "git_sizer": git_sizer,
    }


def print_human_summary(summary: dict[str, Any]) -> None:
    print(f"[repo_audit] ok={summary['ok']}")
    print(
        f"[repo_audit] limits warn={format_bytes(summary['limits']['warn_bytes'])} "
        f"hard={format_bytes(summary['limits']['hard_bytes'])}"
    )
    if summary["large_blobs"]:
        print("[repo_audit] large reachable blobs:")
        for blob in summary["large_blobs"]:
            print(f"  - {blob['path']} ({format_bytes(blob['size_bytes'])})")
    if summary["secret_findings"]:
        print("[repo_audit] secret findings:")
        for finding in summary["secret_findings"][:10]:
            print(
                f"  - {finding['rule_id']} {finding['path']}:{finding['start_line']}"
            )
    if summary["tracked_ignored"]:
        print("[repo_audit] tracked files matching ignore rules:")
        for path in summary["tracked_ignored"]:
            print(f"  - {path}")
    if summary["missing_ignore_rules"]:
        print("[repo_audit] missing required ignore rules:")
        for rule in summary["missing_ignore_rules"]:
            print(f"  - {rule}")
    if summary["warnings"]:
        print("[repo_audit] warnings:")
        for warning in summary["warnings"]:
            print(f"  - {warning}")
    if summary["failures"]:
        print("[repo_audit] failures:")
        for failure in summary["failures"]:
            print(f"  - {failure}")
    if summary["git_sizer"] is not None:
        print("[repo_audit] git-sizer summary captured")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Audit repo push readiness.")
    parser.add_argument("--json", action="store_true", dest="json_output")
    parser.add_argument("--strict", action="store_true")
    parser.add_argument("--warn-limit-bytes", type=int, default=DEFAULT_WARN_LIMIT_BYTES)
    parser.add_argument("--hard-limit-bytes", type=int, default=DEFAULT_HARD_LIMIT_BYTES)
    parser.add_argument("--skip-gitleaks", action="store_true")
    parser.add_argument("--skip-git-sizer", action="store_true")
    args = parser.parse_args(argv)

    summary = build_summary(
        warn_limit_bytes=args.warn_limit_bytes,
        hard_limit_bytes=args.hard_limit_bytes,
        include_gitleaks=not args.skip_gitleaks,
        include_git_sizer=not args.skip_git_sizer,
    )
    if args.json_output:
        print(json.dumps(summary, indent=2, sort_keys=True))
    else:
        print_human_summary(summary)

    if args.strict and not summary["ok"]:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

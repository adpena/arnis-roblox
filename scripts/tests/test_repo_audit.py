#!/usr/bin/env python3
from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from scripts import repo_audit


class RepoAuditTests(unittest.TestCase):
    def test_parse_large_blob_rows(self) -> None:
        rows = (
            "113263158\troblox/src/ServerStorage/SampleData/AustinManifest.lua\n"
            "68558314\trust/out/austin-manifest.json\n"
        )

        blobs = repo_audit.parse_large_blob_rows(rows)

        self.assertEqual(
            blobs,
            [
                repo_audit.BlobFinding(
                    path="roblox/src/ServerStorage/SampleData/AustinManifest.lua",
                    size_bytes=113263158,
                ),
                repo_audit.BlobFinding(
                    path="rust/out/austin-manifest.json",
                    size_bytes=68558314,
                ),
            ],
        )

    def test_missing_ignore_rules_are_reported(self) -> None:
        missing = repo_audit.find_missing_ignore_rules(
            ".venv/\nrust/out/\n",
            ["rust/out/", "out/", ".env", "*.pem", "rust/fuzz/artifacts/", "rust/fuzz/corpus/"],
        )

        self.assertEqual(
            missing,
            ["out/", ".env", "*.pem", "rust/fuzz/artifacts/", "rust/fuzz/corpus/"],
        )

    def test_gitleaks_report_is_loaded(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            report_path = Path(tmp_dir) / "gitleaks.json"
            report_path.write_text(
                json.dumps(
                    [
                        {
                            "RuleID": "github-pat",
                            "Description": "GitHub token",
                            "File": "README.md",
                            "StartLine": 12,
                        }
                    ]
                )
            )

            findings = repo_audit.load_gitleaks_report(report_path)

        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].rule_id, "github-pat")
        self.assertEqual(findings[0].path, "README.md")
        self.assertEqual(findings[0].start_line, 12)

    def test_push_readiness_marks_hard_failures(self) -> None:
        summary = repo_audit.evaluate_push_readiness(
            hard_limit_bytes=100,
            warn_limit_bytes=50,
            large_blobs=[
                repo_audit.BlobFinding(path="huge.bin", size_bytes=150),
                repo_audit.BlobFinding(path="warn.bin", size_bytes=75),
            ],
            secret_findings=[
                repo_audit.SecretFinding(
                    rule_id="github-pat",
                    description="GitHub token",
                    path="README.md",
                    start_line=1,
                )
            ],
            tracked_ignored=["out/generated.txt"],
            missing_ignore_rules=[".env"],
        )

        self.assertFalse(summary.ok)
        self.assertIn("Large reachable blobs exceed hard limit", summary.failures[0])
        self.assertIn("Secret findings detected in reachable history", summary.failures[1])
        self.assertIn("Tracked files match ignore rules", summary.failures[2])
        self.assertIn("Missing required ignore rules", summary.failures[3])
        self.assertIn("warn.bin", summary.warnings[0])

    def test_staged_deletions_are_filtered_from_tracked_ignored(self) -> None:
        remaining = repo_audit.exclude_staged_deletions(
            tracked_ignored=["out/generated.txt", "tmp/artifact.bin", "README.md"],
            staged_deletions={"out/generated.txt", "tmp/artifact.bin"},
        )

        self.assertEqual(remaining, ["README.md"])


if __name__ == "__main__":
    unittest.main()

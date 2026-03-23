#!/usr/bin/env python3
from __future__ import annotations

import unittest

from scripts import run_austin_stress


class AustinStressTests(unittest.TestCase):
    def test_edit_marker_detection_ignores_startup_noise(self) -> None:
        lines = [
            "2026-03-19T22:11:39.646Z startup",
            "[VertigoSync] Plugin initialized. version=2026-03-10-v7-resync-hardening mode=edit+server ws=unavailable",
            "The MCP Studio plugin is ready for prompts.",
        ]
        self.assertFalse(run_austin_stress.has_edit_markers(lines))

    def test_edit_marker_detection_requires_explicit_edit_activity(self) -> None:
        lines = [
            "2026-03-19T22:11:39.646Z startup",
            'ARNIS_MCP_EDIT_ACTION {"runAll":{"total":1,"passed":1,"failed":0},"preview":{"status":"ok"}}',
        ]
        self.assertTrue(run_austin_stress.has_edit_markers(lines))

    def test_runtime_marker_detection_ignores_startup_noise(self) -> None:
        lines = [
            "2026-03-19T22:11:39.646Z,0.646828,516f100,6,Error [FLog::Error] Redundant Flag ID: ACE3DImporter",
            "2026-03-19T22:11:40.331Z,1.331268,6e487000,6,Warning [FLog::StudioCommands] Unable to find component MaterialGenerator in histogram map.",
        ]
        self.assertFalse(run_austin_stress.has_runtime_markers(lines))

    def test_runtime_marker_detection_requires_real_play_markers(self) -> None:
        lines = [
            "2026-03-19T22:11:39.646Z startup",
            "PlaceStateTransitionStatus becomes StartingPlayTest",
            "[BootstrapAustin] Starting Austin, TX import...",
        ]
        self.assertTrue(run_austin_stress.has_runtime_markers(lines))

    def test_parse_perf_summary(self) -> None:
        line = (
            "[RunAustin] Perf summary: refs=885 imported=112 total=29141.7ms "
            "hot=ImportManifest 27230.2ms slowest=ImportManifest 27230.2ms"
        )
        result = run_austin_stress.parse_perf_summary(line)
        assert result is not None
        self.assertEqual(result.refs, 885)
        self.assertEqual(result.imported, 112)
        self.assertAlmostEqual(result.total_ms, 29141.7)
        self.assertEqual(result.hot_label, "ImportManifest")

    def test_parse_anchor_line(self) -> None:
        line = "[RunAustin] Austin anchor: focus=(5.7, 0.0, -178.2) spawn=(5.7, 0.0, -178.2)"
        result = run_austin_stress.parse_anchor_line(line)
        assert result is not None
        self.assertAlmostEqual(result.focus["x"], 5.7)
        self.assertAlmostEqual(result.spawn["z"], -178.2)

    def test_collects_json_markers(self) -> None:
        lines = [
            'ARNIS_MCP_EDIT_ACTION {"runAll":{"total":1,"passed":1,"failed":0},"preview":{"status":"ok","children":52}}',
            'ARNIS_MCP_EDIT {"generatedExists":true,"generatedChildren":50,"austinSpawnX":6}',
            'ARNIS_MCP_PLAY {"generatedExists":true,"generatedChildren":112,"austinSpawnX":6}',
            'ARNIS_MCP_PLAY_LATE {"generatedExists":true,"ground":{"distance":4.1}}',
        ]
        iteration = run_austin_stress.parse_iteration(lines)
        self.assertEqual(iteration["edit_action"]["runAll"]["passed"], 1)
        self.assertTrue(iteration["edit"]["generatedExists"])
        self.assertEqual(iteration["play"]["generatedChildren"], 112)
        self.assertAlmostEqual(iteration["play_late"]["ground"]["distance"], 4.1)

    def test_evaluate_iteration_flags_missing_runtime_state(self) -> None:
        iteration = {
            "perf": None,
            "anchor": None,
            "edit_markers": False,
            "runtime_markers": False,
            "edit_action": None,
            "edit": {"generatedExists": True},
            "play": {"generatedExists": False, "root": None},
            "play_late": {"loadingPad": {"x": 0, "y": 300, "z": 0}},
        }
        failures = run_austin_stress.evaluate_iteration(iteration)
        self.assertTrue(any("Edit markers missing" in failure for failure in failures))
        self.assertTrue(any("Runtime markers missing" in failure for failure in failures))
        self.assertTrue(any("Perf summary missing" in failure for failure in failures))
        self.assertTrue(any("Runtime anchor missing" in failure for failure in failures))
        self.assertTrue(any("Play probe did not observe generated Austin world" in failure for failure in failures))
        self.assertTrue(any("AustinLoadingPad still present late in play probe" in failure for failure in failures))


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
from __future__ import annotations

import re
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
HARNESS_PATH = ROOT / "scripts" / "run_studio_harness.sh"


class RunStudioHarnessTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.text = HARNESS_PATH.read_text(encoding="utf-8")

    def test_capture_mcp_probe_uses_shared_stop_decision_policy(self) -> None:
        match = re.search(
            r"capture_mcp_probe\(\) \{\n(?P<body>.*?)\n\}\n\nrun_probe_best_effort",
            self.text,
            re.DOTALL,
        )
        self.assertIsNotNone(match, "capture_mcp_probe function not found")
        body = match.group("body")
        self.assertIn('MCP_PREFLIGHT_SESSION_STATUS="$preflight_session_status"', body)
        self.assertIn('MCP_LOG_INDICATES_PLAY="$preflight_log_indicates_play"', body)
        self.assertIn("from studio_harness_policy import mcp_mode_stop_decision", body)
        self.assertIn("mcp_mode_stop_decision(", body)
        self.assertIn('if phase == "edit" and decision == "ignore":', body)
        self.assertNotIn(
            'if current_mode == "stop":\n        print(f"[harness-mcp] phase={phase} skip=studio-stop")',
            body,
        )

    def test_hard_restart_uses_force_quit_path(self) -> None:
        self.assertIn("force_quit_studio()", self.text)
        self.assertIn('failed to fully force-quit Roblox Studio before hard restart', self.text)
        takeover_block = re.search(
            r'if \[\[ \$DO_RESTART -eq 1 \|\| \$HARD_RESTART -eq 1 \]\]; then\n(?P<body>.*?)\n  else',
            self.text,
            re.DOTALL,
        )
        self.assertIsNotNone(takeover_block, "restart/takeover block not found")
        body = takeover_block.group("body")
        self.assertIn("if [[ $HARD_RESTART -eq 1 ]]; then", body)
        self.assertIn("force_quit_studio", body)
        self.assertIn("quit_studio", body)
        self.assertIn("if ! force_quit_studio; then", body)

    def test_edit_action_reconciles_against_log_backed_success(self) -> None:
        self.assertIn("edit_action_completed_successfully_in_log()", self.text)
        self.assertIn('from studio_harness_policy import is_successful_edit_action_payload', self.text)
        self.assertIn("if edit_action_completed_successfully_in_log; then", self.text)
        self.assertIn(
            "edit-mode MCP transport failed after log-backed completion; accepting current edit result",
            self.text,
        )

    def test_successful_edit_action_skips_redundant_probe(self) -> None:
        self.assertIn(
            'if [[ $edit_actions_via_mcp -eq 1 ]] && edit_action_completed_successfully_in_log; then',
            self.text,
        )
        self.assertIn("skipping redundant edit MCP probe after successful log-backed edit action", self.text)

    def test_open_studio_verifies_target_place_before_success(self) -> None:
        self.assertIn("studio_opened_target_place()", self.text)
        self.assertIn('front_window="$(studio_session_status_value front_window)"', self.text)
        self.assertIn('place_basename="$(basename "$PLACE_PATH")"', self.text)

    def test_edit_mcp_run_code_timeout_matches_real_preview_budget(self) -> None:
        self.assertIn("timeout_seconds=max(edit_wait_seconds + 90, 120)", self.text)

    def test_harness_manages_vsync_serve_lifecycle_for_fresh_process_bootstrap(self) -> None:
        self.assertIn("ensure_vsync_server_running()", self.text)
        self.assertIn("stop_vsync_server()", self.text)
        self.assertIn('curl -sf "$VSYNC_SERVER_URL/project"', self.text)
        self.assertIn('VSYNC_SERVER_PID=""', self.text)
        self.assertIn("resolve_vsync_server_url()", self.text)
        self.assertIn("ensure_vsync_server_running", self.text)
        self.assertIn("stop_vsync_server", self.text)

    def test_harness_does_not_ignore_vsync_plugin_install_failure(self) -> None:
        self.assertIn("ensure_vsync_plugin_installed()", self.text)
        self.assertNotIn("ensure_vsync_plugin_installed || true", self.text)

    def test_emit_scene_markers_split_large_roof_coverage_payloads(self) -> None:
        self.assertIn('print(marker .. "_SCALAR " .. HttpService:JSONEncode({', self.text)
        self.assertIn('print(marker .. "_ROOF_USAGE_BUCKET " .. HttpService:JSONEncode({', self.text)
        self.assertIn('print(marker .. "_ROOF_SHAPES " .. HttpService:JSONEncode({', self.text)
        self.assertIn('print(marker .. "_WATER_TYPE_BUCKET " .. HttpService:JSONEncode({', self.text)
        self.assertIn('print(marker .. "_WATER_KIND_BUCKET " .. HttpService:JSONEncode({', self.text)
        self.assertIn('emitSourceIdBatches(marker, "_WATER_KIND_IDS_BATCH"', self.text)
        self.assertIn('print(marker .. "_ROAD_KIND_BUCKET " .. HttpService:JSONEncode({', self.text)
        self.assertIn('emitSourceIdBatches(marker, "_ROAD_KIND_IDS_BATCH"', self.text)
        self.assertIn('print(marker .. "_ROAD_SUBKIND_BUCKET " .. HttpService:JSONEncode({', self.text)
        self.assertIn('emitSourceIdBatches(marker, "_ROAD_SUBKIND_IDS_BATCH"', self.text)
        self.assertIn('key ~= "buildingRoofCoverageByUsage"', self.text)
        self.assertIn('key ~= "buildingRoofCoverageByShape"', self.text)
        self.assertIn('print(marker .. "_PROP_KIND_BUCKET " .. HttpService:JSONEncode({', self.text)
        self.assertIn('emitSourceIdBatches(marker, "_PROP_KIND_IDS_BATCH"', self.text)
        self.assertIn('print(marker .. "_AMBIENT_PROP_KIND_BUCKET " .. HttpService:JSONEncode({', self.text)
        self.assertIn('print(marker .. "_TREE_SPECIES_BUCKET " .. HttpService:JSONEncode({', self.text)
        self.assertIn('emitSourceIdBatches(marker, "_TREE_SPECIES_IDS_BATCH"', self.text)
        self.assertIn('print(marker .. "_VEGETATION_KIND_BUCKET " .. HttpService:JSONEncode({', self.text)
        self.assertIn('emitSourceIdBatches(marker, "_VEGETATION_KIND_IDS_BATCH"', self.text)
        self.assertIn('key ~= "waterSurfacePartCountByType"', self.text)
        self.assertIn('key ~= "waterSurfacePartCountByKind"', self.text)
        self.assertIn('key ~= "roadSurfacePartCountByKind"', self.text)
        self.assertIn('key ~= "roadSurfacePartCountBySubkind"', self.text)
        self.assertIn('key ~= "propInstanceCountByKind"', self.text)
        self.assertIn('key ~= "ambientPropInstanceCountByKind"', self.text)
        self.assertIn('key ~= "treeInstanceCountBySpecies"', self.text)
        self.assertIn('key ~= "vegetationInstanceCountByKind"', self.text)
        self.assertIn('statsKey ~= "_sourceIdSet"', self.text)

    def test_emit_source_id_batches_use_character_budget_not_fixed_count(self) -> None:
        self.assertIn("local MAX_SCENE_ID_BATCH_CHARS = 700", self.text)
        self.assertIn("local candidatePayload = {", self.text)
        self.assertIn('local candidateJson = HttpService:JSONEncode(candidatePayload)', self.text)
        self.assertIn("if string.len(candidateJson) > MAX_SCENE_ID_BATCH_CHARS and #batch > 1 then", self.text)
        self.assertNotIn("local batchSize = 64", self.text)

    def test_scene_marker_luau_is_defined_once_and_shared(self) -> None:
        self.assertIn("read -r -d '' SCENE_MARKER_LUAU <<'LUA' || true", self.text)
        self.assertEqual(
            len(re.findall(r"local function emitSceneMarkers\(", self.text)),
            1,
            "expected one shared emitSceneMarkers implementation in the harness",
        )

    def test_edit_action_payload_uses_compact_preview_summary(self) -> None:
        self.assertIn("sceneSummary = {", self.text)
        self.assertIn("buildingModelCount = scene and scene.buildingModelCount or 0", self.text)
        self.assertIn("roadSurfacePartCount = scene and scene.roadSurfacePartCount or 0", self.text)
        self.assertNotIn("scene = scene,", self.text)

    def test_harness_validates_preview_rebuild_reasons(self) -> None:
        self.assertIn("validate_preview_rebuild_behavior()", self.text)
        self.assertIn('marker = "Preview rebuilt ("', self.text)
        self.assertIn('if reason == "project_bootstrap":', self.text)
        self.assertIn('if bootstrap_count > 1:', self.text)
        self.assertIn("unexpected preview rebuild reasons", self.text)


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
from __future__ import annotations

import re
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
HARNESS_PATH = ROOT / "scripts" / "run_studio_harness.sh"
POLICY_PATH = ROOT / "scripts" / "studio_harness_policy.py"


class RunStudioHarnessTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.text = HARNESS_PATH.read_text(encoding="utf-8")
        cls.policy_text = POLICY_PATH.read_text(encoding="utf-8")

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
        self.assertIn("should_reuse_vsync_server()", self.text)
        self.assertIn("terminate_stale_vsync_listener()", self.text)
        self.assertIn("recover_vsync_server_for_edit_readiness()", self.text)
        self.assertIn("vsync_project_endpoint_ready()", self.text)
        self.assertIn("Vertigo Sync server is unreachable during edit readiness; restarting it before retry", self.text)
        self.assertIn('VSYNC_SERVER_LOG="$(mktemp -t arnis-vsync-serve)"', self.text)
        self.assertIn('curl -sf "$VSYNC_SERVER_URL/project"', self.text)
        self.assertIn('VSYNC_SERVER_PID=""', self.text)
        self.assertIn("resolve_vsync_server_url()", self.text)
        self.assertIn("ensure_vsync_server_running", self.text)
        self.assertIn("stop_vsync_server", self.text)

    def test_edit_mode_waits_for_vsync_readiness_before_mcp_actions(self) -> None:
        self.assertIn("wait_for_vsync_edit_readiness()", self.text)
        self.assertIn("recover_vsync_server_for_edit_readiness()", self.text)
        self.assertIn("wait_for_readiness(", self.policy_text)
        self.assertIn('/readiness?target=', self.policy_text)
        self.assertIn("build_readiness_expectation(", self.policy_text)
        self.assertIn("expected_target", self.policy_text)
        self.assertIn("expected_epoch", self.policy_text)
        self.assertIn("expected_incarnation_id", self.policy_text)
        self.assertIn('"readiness": readiness', self.text)
        self.assertIn(
            'wait_for_log_pattern "\\\\[VertigoSync\\\\] Snapshot reconciled|\\\\[VertigoSync\\\\] Plugin initialized"',
            self.text,
        )
        self.assertIn("edit-mode setup did not reach Vertigo Sync readiness before timeout", self.text)
        self.assertIn(
            "edit-mode setup did not reach Vertigo Sync readiness before timeout; attempting Vertigo Sync recovery",
            self.text,
        )
        self.assertIn("recover_vsync_server_for_edit_readiness || {", self.text)
        self.assertIn("Studio MCP helper did not become ready after Vertigo Sync recovery; retrying readiness anyway", self.text)
        readiness_index = self.text.find(
            'if edit_readiness_json="$(VSYNC_EDIT_READINESS_TARGET="$edit_readiness_target" wait_for_vsync_edit_readiness)"; then'
        )
        mcp_index = self.text.find(
            'client.call_tool(\n        "run_code",\n        {"command": luau, "readiness": readiness},'
        )
        self.assertGreaterEqual(readiness_index, 0, "expected edit-mode flow to wait for Vertigo Sync readiness")
        self.assertGreaterEqual(mcp_index, 0, "expected edit-mode flow to invoke MCP edit actions")
        self.assertLess(
            readiness_index,
            mcp_index,
            "expected Vertigo Sync readiness gating before edit-mode MCP actions",
        )

    def test_vsync_readiness_policy_builds_authoritative_mcp_expectation(self) -> None:
        self.assertIn("def fetch_readiness(", self.policy_text)
        self.assertIn("def wait_for_readiness(", self.policy_text)
        self.assertIn("def build_readiness_expectation(", self.policy_text)
        self.assertIn("from urllib import request", self.policy_text)
        self.assertIn("request.urlopen", self.policy_text)
        self.assertIn("/readiness?target=", self.policy_text)
        self.assertIn("expected_target", self.policy_text)
        self.assertIn("expected_epoch", self.policy_text)
        self.assertIn("expected_incarnation_id", self.policy_text)

    def test_harness_samples_memory_and_enforces_configurable_budget(self) -> None:
        self.assertIn('MEMORY_LIMIT_MB="${HARNESS_MEMORY_LIMIT_MB:-4096}"', self.text)
        self.assertIn('MEMORY_SAMPLE_SECONDS="${HARNESS_MEMORY_SAMPLE_SECONDS:-2}"', self.text)
        self.assertIn('ALLOW_HEAVY_PREVIEW_SOURCE="${HARNESS_ALLOW_HEAVY_PREVIEW_SOURCE:-0}"', self.text)
        self.assertIn("--memory-limit-mb MB", self.text)
        self.assertIn("--memory-sample-sec SEC", self.text)
        self.assertIn("sample_harness_memory_json()", self.text)
        self.assertIn("sample_harness_host_probe_json()", self.text)
        self.assertIn('host_probe_json="$(sample_harness_host_probe_json)"', self.text)
        self.assertIn('HARNESS_HOST_PROBE_JSON="$host_probe_json"', self.text)
        self.assertIn('host_probe_sample = json.loads(os.environ.get("HARNESS_HOST_PROBE_JSON", "{}"))', self.text)
        self.assertIn('Workspace:SetAttribute("ArnisStreamingHostProbeAvailableBytes", hostProbeSample.availableBytes)', self.text)
        self.assertIn('Workspace:SetAttribute("ArnisStreamingHostProbePressureLevel", hostProbeSample.pressureLevel)', self.text)
        self.assertIn("payload.hostProbe = hostProbeSample", self.text)
        self.assertIn('"availableBytes": available_bytes,', self.text)
        self.assertIn('"pressureLevel": pressure_level,', self.text)
        self.assertIn("start_memory_monitor()", self.text)
        self.assertIn("stop_memory_monitor()", self.text)
        self.assertIn("summarize_memory_monitor()", self.text)
        self.assertIn('kill -TERM "$parent_pid"', self.text)
        self.assertIn("aggregate harness RSS exceeded budget:", self.text)
        self.assertIn('"[harness] memory peaks "', self.text)
        self.assertIn('f"total={peak_total / 1024:.1f}MB "', self.text)
        self.assertIn("start_memory_monitor", self.text)
        self.assertIn("stop_memory_monitor", self.text)
        self.assertIn("summarize_memory_monitor", self.text)

    def test_harness_captures_preview_telemetry_artifacts(self) -> None:
        self.assertIn("capture_preview_telemetry_artifacts()", self.text)
        self.assertIn('local preview_telemetry_dir="${ARNIS_PREVIEW_TELEMETRY_DIR:-/tmp}"', self.text)
        self.assertIn('curl -sf "$VSYNC_SERVER_URL/plugin/state"', self.text)
        self.assertIn('local plugin_state_json="$preview_telemetry_dir/arnis-preview-plugin-state.json"', self.text)
        self.assertIn('local telemetry_summary_txt="$preview_telemetry_dir/arnis-preview-telemetry-summary.txt"', self.text)
        self.assertIn('log "preview telemetry saved: $plugin_state_json"', self.text)
        self.assertIn('log "preview telemetry summary: $(cat "$telemetry_summary_txt")"', self.text)

    def test_harness_does_not_ignore_vsync_plugin_install_failure(self) -> None:
        self.assertIn("ensure_vsync_plugin_installed()", self.text)
        self.assertNotIn("ensure_vsync_plugin_installed || true", self.text)

    def test_harness_defaults_to_clean_preview_without_edit_mode_runall(self) -> None:
        self.assertIn("--edit-tests", self.text)
        self.assertIn("--skip-edit-tests", self.text)
        self.assertIn("RUNALL_EDIT_ENABLED=0", self.text)
        self.assertIn("RUNALL_EDIT_ENABLED=1", self.text)
        self.assertIn("set_runall_config_modes \"$edit_enabled\" \"$play_enabled\"", self.text)

    def test_harness_supports_optional_luau_spec_filter(self) -> None:
        self.assertIn("--spec-filter NAME", self.text)
        self.assertIn('RUNALL_SPEC_FILTER=""', self.text)
        self.assertIn('RUNALL_SPEC_FILTER="$2"', self.text)
        self.assertIn('set_runall_config_filter "$RUNALL_SPEC_FILTER"', self.text)
        self.assertIn('runall_spec_filter = os.environ.get("RUNALL_SPEC_FILTER", "").strip()', self.text)
        self.assertIn("local runAllSpecFilter = ", self.text)
        self.assertIn("specNameFilter = runAllSpecFilter", self.text)

    def test_runall_entry_edit_mode_is_disabled_when_mcp_drives_edit_tests(self) -> None:
        self.assertIn('if [[ $RUNALL_EDIT_ENABLED -eq 0 || -n "$MCP_BINARY" ]]; then', self.text)

    def test_non_preview_edit_specs_can_fallback_to_runall_entry_when_mcp_bridge_is_unready(self) -> None:
        self.assertIn('MCP_READY=0', self.text)
        self.assertIn("can_run_runall_entry_edit_fallback()", self.text)
        self.assertIn('[[ $RUNALL_EDIT_ENABLED -eq 1 ]]', self.text)
        self.assertIn('[[ -n "$RUNALL_SPEC_FILTER" ]]', self.text)
        self.assertIn('[[ "$RUNALL_SPEC_FILTER" == *Preview* ]]', self.text)
        self.assertIn("run_edit_actions_via_runall_entry()", self.text)
        self.assertIn('set_runall_config_modes true false', self.text)
        self.assertIn('triggered edit-mode actions via RunAllEntry fallback', self.text)
        self.assertIn('if [[ -z "$MCP_BINARY" || ! -x "$MCP_BINARY" || $MCP_READY -ne 1 ]]; then', self.text)

    def test_harness_tracks_real_mcp_bridge_readiness_before_using_edit_actions(self) -> None:
        self.assertIn('MCP_READY_WAIT_SECONDS="${HARNESS_MCP_READY_WAIT_SECONDS:-12}"', self.text)
        self.assertIn('MCP_READY=1', self.text)
        self.assertIn('MCP_READY=0', self.text)
        self.assertIn('Studio MCP helper did not become ready after initial launch; edit-mode MCP actions will stay disabled', self.text)
        self.assertIn('Studio MCP helper did not become ready after relaunch; edit-mode MCP actions will stay disabled', self.text)
        self.assertIn('while [[ $waited -lt $MCP_READY_WAIT_SECONDS ]]; do', self.text)

    def test_edit_mcp_path_skips_preview_probe_for_non_preview_isolated_specs(self) -> None:
        self.assertIn('run_preview_probe = runall_spec_filter == "" or "Preview" in runall_spec_filter', self.text)
        self.assertIn("local runPreviewProbe = ", self.text)
        self.assertIn("if runPreviewProbe then", self.text)
        self.assertIn('status = "skipped"', self.text)
        self.assertIn('skipReason = "spec_filter_non_preview"', self.text)

    def test_play_probe_samples_bootstrap_state_attributes(self) -> None:
        self.assertIn('payload.austinBootstrapState = Workspace:GetAttribute("ArnisAustinBootstrapState")', self.text)
        self.assertIn('payload.austinBootstrapStateOrder = Workspace:GetAttribute("ArnisAustinBootstrapStateOrder")', self.text)
        self.assertIn('payload.austinBootstrapFailure = Workspace:GetAttribute("ArnisAustinBootstrapFailure")', self.text)
        self.assertIn('payload.austinBootstrapEntryCount = Workspace:GetAttribute("ArnisAustinBootstrapEntryCount")', self.text)
        self.assertIn(
            'payload.austinBootstrapDuplicateCount = Workspace:GetAttribute("ArnisAustinBootstrapDuplicateCount")',
            self.text,
        )

    def test_play_fallback_waits_for_explicit_bootstrap_terminal_states(self) -> None:
        self.assertIn(
            'wait_for_log_pattern "\\\\[BootstrapAustin\\\\] state=gameplay_ready|\\\\[BootstrapAustin\\\\] state=failed"',
            self.text,
        )
        self.assertNotIn(
            'wait_for_log_pattern "\\\\[BootstrapAustin\\\\] Starting Austin, TX import|\\\\[RunAustin\\\\]|\\\\[BootstrapAustin\\\\] Done\\\\."',
            self.text,
        )

    def test_auto_built_clean_place_uses_one_canonical_output_path(self) -> None:
        self.assertIn('local output_place="$roblox_dir/out/arnis-test-clean-$output_suffix.rbxlx"', self.text)
        self.assertIn('local output_suffix="edit"', self.text)
        self.assertIn('output_suffix="play"', self.text)
        self.assertIn('"$VSYNC_BINARY" --root "$roblox_dir" build --project "$build_project" --output "$output_place"', self.text)
        self.assertIn('printf \'%s\\n\' "$output_place"', self.text)
        self.assertIn('if output_place="$(build_clean_place "$include_runtime_sample_data")"; then', self.text)
        self.assertNotIn("--project out/default.build.project.json --output out/arnis-test-clean.rbxlx", self.text)

    def test_edit_only_auto_build_omits_runtime_sample_data_from_clean_place(self) -> None:
        self.assertIn('local include_runtime_sample_data="${1:-true}"', self.text)
        self.assertIn('python3 "$ROOT_DIR/scripts/generate_harness_projects.py" "${harness_project_args[@]}"', self.text)
        self.assertIn('harness_project_args+=(--include-runtime-sample-data)', self.text)
        self.assertIn('if [[ $DO_PLAY -eq 0 ]]; then', self.text)
        self.assertIn('include_runtime_sample_data="false"', self.text)

    def test_harness_uses_dedicated_vsync_serve_project_with_compiled_fixture_ignores(self) -> None:
        self.assertIn('local serve_project="$roblox_dir/.harness.serve.project.json"', self.text)
        self.assertIn('python3 "$ROOT_DIR/scripts/generate_harness_projects.py" "${harness_project_args[@]}"', self.text)
        self.assertIn('if [[ -f "$serve_project" ]]; then', self.text)
        self.assertIn('exec "$VSYNC_BINARY" serve --project "$serve_project"', self.text)
        self.assertIn('exec "$VSYNC_BINARY" serve --project default.project.json', self.text)

    def test_generated_harness_projects_live_beside_default_project_for_stable_relative_paths(self) -> None:
        self.assertIn('local build_project="$roblox_dir/.harness.build.project.json"', self.text)
        self.assertIn('local serve_project="$roblox_dir/.harness.serve.project.json"', self.text)
        self.assertIn('--build-project "$build_project"', self.text)
        self.assertIn('--serve-project "$serve_project"', self.text)
        self.assertIn('--default-project "$roblox_dir/default.project.json"', self.text)
        self.assertNotIn("def rebase_path(path_value: str) -> str:", self.text)

    def test_emit_scene_markers_split_large_roof_coverage_payloads(self) -> None:
        self.assertIn('print(marker .. "_SCALAR " .. HttpService:JSONEncode({', self.text)
        self.assertIn('print(marker .. "_ROOF_USAGE_BUCKET " .. HttpService:JSONEncode({', self.text)
        self.assertIn('print(marker .. "_ROOF_SHAPES " .. HttpService:JSONEncode({', self.text)
        self.assertIn('print(marker .. "_WATER_TYPE_BUCKET " .. HttpService:JSONEncode({', self.text)
        self.assertIn('print(marker .. "_WATER_KIND_BUCKET " .. HttpService:JSONEncode({', self.text)
        self.assertIn('emitSourceIdBatches(marker, "_WATER_KIND_IDS_BATCH"', self.text)
        self.assertIn('print(marker .. "_RAIL_KIND_BUCKET " .. HttpService:JSONEncode({', self.text)
        self.assertIn('emitSourceIdBatches(marker, "_RAIL_KIND_IDS_BATCH"', self.text)
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
        self.assertIn('key ~= "railReceiptCountByKind"', self.text)
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

    def test_preview_rebuild_validation_distinguishes_geometry_reasons(self) -> None:
        self.assertIn("is_geometry_affecting_preview_rebuild_reason", self.text)
        self.assertIn('reason == "project_bootstrap"', self.text)
        self.assertIn('reason == "workspace_attribute"', self.text)
        self.assertIn('reason.startswith("source_changed:")', self.text)
        self.assertIn('reason.startswith("descendant_added:")', self.text)
        self.assertIn('reason.startswith("descendant_removed:")', self.text)
        self.assertIn("unexpected_reasons.append(reason)", self.text)

    def test_scene_fidelity_audits_support_configurable_output_dir(self) -> None:
        self.assertIn('local scene_audit_dir="${ARNIS_SCENE_AUDIT_DIR:-/tmp}"', self.text)
        self.assertIn('mkdir -p "$scene_audit_dir"', self.text)
        self.assertIn('local edit_json="$scene_audit_dir/arnis-scene-fidelity-edit.json"', self.text)
        self.assertIn('local edit_html="$scene_audit_dir/arnis-scene-fidelity-edit.html"', self.text)
        self.assertIn('local play_json="$scene_audit_dir/arnis-scene-fidelity-play.json"', self.text)
        self.assertIn('local play_html="$scene_audit_dir/arnis-scene-fidelity-play.html"', self.text)

    def test_scene_fidelity_audits_prefer_sqlite_manifest_store_when_available(self) -> None:
        self.assertIn('local manifest_sqlite_path="$ROOT_DIR/rust/out/austin-manifest.sqlite"', self.text)
        self.assertIn('local manifest_scene_index_args=()', self.text)
        self.assertIn('manifest_scene_index_args=(--manifest-sqlite "$manifest_sqlite_path")', self.text)
        self.assertIn('manifest_scene_index_args=(--manifest "$manifest_path")', self.text)
        self.assertIn('"${manifest_scene_index_args[@]}"', self.text)

    def test_harness_fails_fast_on_heavy_preview_source_unless_explicitly_allowed(self) -> None:
        self.assertIn("preview_source_looks_heavy()", self.text)
        self.assertIn('HARNESS_ALLOW_HEAVY_PREVIEW_SOURCE=1', self.text)
        self.assertIn('if [[ "$ALLOW_HEAVY_PREVIEW_SOURCE" != "1" ]] && preview_source_looks_heavy; then', self.text)
        self.assertIn('preview source appears to be insane/yolo-grade terrain data', self.text)


if __name__ == "__main__":
    unittest.main()

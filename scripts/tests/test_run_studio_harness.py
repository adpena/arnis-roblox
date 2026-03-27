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

    def test_graceful_quit_reacts_immediately_to_blocked_close_dialog(self) -> None:
        self.assertIn('python3 "$STUDIO_UI_CONTROL" quit >/dev/null 2>&1 || true', self.text)
        self.assertIn('current_status="$(studio_session_status_value status 2>/dev/null || printf \'unknown\')"', self.text)
        self.assertIn('if [[ "$current_status" == "blocked_dialog" ]]; then', self.text)
        self.assertIn('dismiss_startup_dialogs || true', self.text)
        self.assertIn('python3 "$STUDIO_UI_CONTROL" dismiss-dont-save >/dev/null 2>&1 || true', self.text)
        self.assertIn('log "Studio close dialog detected during quit; dismissing without saving"', self.text)

    def test_harness_acquires_single_instance_lock_and_cleans_it_up(self) -> None:
        self.assertIn('HARNESS_LOCK_DIR="${HARNESS_LOCK_DIR:-/tmp/arnis-studio-harness.lock}"', self.text)
        self.assertIn('HARNESS_LOCK_OWNED=0', self.text)
        self.assertIn("acquire_harness_lock()", self.text)
        self.assertIn("release_harness_lock()", self.text)
        self.assertIn('local owner_pid_file="$HARNESS_LOCK_DIR/pid"', self.text)
        self.assertIn('mkdir "$HARNESS_LOCK_DIR"', self.text)
        self.assertIn('echo "[harness] another harness run is already active', self.text)
        self.assertIn("release_harness_lock", self.text)
        self.assertIn("acquire_harness_lock", self.text)
        cleanup_index = self.text.find("release_harness_lock")
        trap_index = self.text.find("trap 'cleanup \"$?\"' EXIT")
        self.assertGreaterEqual(cleanup_index, 0)
        self.assertGreaterEqual(trap_index, 0)
        self.assertLess(cleanup_index, trap_index)

    def test_cleanup_guards_late_defined_helpers_for_early_exit_paths(self) -> None:
        self.assertIn("run_cleanup_helper_if_defined()", self.text)
        self.assertIn('declare -F "$helper_name" >/dev/null 2>&1', self.text)
        self.assertIn("run_cleanup_helper_if_defined stop_log_pipe", self.text)
        self.assertIn("run_cleanup_helper_if_defined stop_memory_monitor", self.text)
        self.assertIn("run_cleanup_helper_if_defined summarize_memory_monitor", self.text)
        self.assertIn("run_cleanup_helper_if_defined release_harness_lock", self.text)
        self.assertIn("run_cleanup_helper_if_defined stop_mcp_sidecar", self.text)
        self.assertIn("run_cleanup_helper_if_defined stop_vsync_server", self.text)
        self.assertIn("run_cleanup_helper_if_defined restore_runall_config", self.text)
        self.assertIn("run_cleanup_helper_if_defined restore_foreign_plugins", self.text)
        self.assertIn('if declare -F studio_session_status_value >/dev/null 2>&1; then', self.text)
        self.assertIn('if [[ "$should_close" == "true" ]] && declare -F quit_studio >/dev/null 2>&1; then', self.text)

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
            'client.call_tool(\n        "run_code",\n        {"command": luau},'
        )
        self.assertGreaterEqual(readiness_index, 0, "expected edit-mode flow to wait for Vertigo Sync readiness")
        self.assertGreaterEqual(mcp_index, 0, "expected edit-mode flow to invoke MCP edit actions")
        self.assertLess(
            readiness_index,
            mcp_index,
            "expected Vertigo Sync readiness gating before edit-mode MCP actions",
        )

    def test_play_harness_uses_edit_sync_when_preview_is_disabled(self) -> None:
        self.assertIn('local edit_readiness_target="preview"', self.text)
        self.assertIn("if [[ $DO_PLAY -eq 1 ]]; then", self.text)
        self.assertIn('edit_readiness_target="edit_sync"', self.text)

    def test_play_focused_runs_skip_edit_mode_actions_when_edit_tests_are_disabled(self) -> None:
        self.assertIn("should_skip_edit_mode_actions_for_play()", self.text)
        self.assertIn("if should_skip_edit_mode_actions_for_play; then", self.text)
        self.assertIn('log "skipping edit-mode actions before play-focused harness run"', self.text)
        self.assertIn("if [[ $DO_PLAY -ne 1 ]]; then", self.text)
        self.assertIn("if [[ $RUNALL_EDIT_ENABLED -ne 0 ]]; then", self.text)
        self.assertIn('if [[ -n "$RUNALL_SPEC_FILTER" ]]; then', self.text)

    def test_edit_mode_does_not_pass_unsupported_readiness_argument_to_mcp_run_code(self) -> None:
        self.assertIn("readiness = build_readiness_expectation(readiness_record)", self.text)
        self.assertIn('print(f"[harness-mcp] phase=edit readiness={json.dumps(readiness, separators=(\',\', \':\'))}")', self.text)
        self.assertIn('"run_code",', self.text)
        self.assertNotIn('{"command": luau, "readiness": readiness}', self.text)

    def test_edit_mode_wraps_mcp_luau_in_xpcall_traceback(self) -> None:
        self.assertIn("local function __arnis_main__()", self.text)
        self.assertIn('local ok, err = xpcall(__arnis_main__, function(runtimeError)', self.text)
        self.assertIn('print("ARNIS_MCP_EDIT_TRACEBACK " .. err)', self.text)

    def test_edit_mode_uses_loadstring_compatible_preview_summary_syntax(self) -> None:
        self.assertIn('local previewStatus = "ok"', self.text)
        self.assertIn("local childCount = 0", self.text)
        self.assertNotIn('status = if waitError then "timeout" else "ok"', self.text)

    def test_edit_mode_embeds_host_probe_as_jsondecode_not_raw_json_table(self) -> None:
        self.assertIn('local hostProbeSample = HttpService:JSONDecode(', self.text)
        self.assertNotIn('local hostProbeSample = {"availableBytes":', self.text)

    def test_edit_mode_reuses_settled_preview_instead_of_forcing_rebuild(self) -> None:
        self.assertIn("local function currentPreviewSyncIsSettled()", self.text)
        self.assertIn("local existingRoot = currentPreviewSyncIsSettled()", self.text)
        self.assertIn('resultType = existingRoot and "existing" or typeof(previewResult)', self.text)

    def test_harness_runs_persistent_mcp_sidecar_for_plugin_relay(self) -> None:
        self.assertIn("mcp_sidecar_port_open()", self.text)
        self.assertIn("start_mcp_sidecar()", self.text)
        self.assertIn("stop_mcp_sidecar()", self.text)
        self.assertIn('"$MCP_BINARY" --stdio', self.text)
        self.assertIn('start_mcp_sidecar || true', self.text)
        self.assertIn('log "started Studio MCP sidecar on localhost:44755"', self.text)
        self.assertIn('log "Studio MCP sidecar failed to expose localhost:44755; continuing without persistent relay"', self.text)
        cleanup_index = self.text.find("stop_mcp_sidecar")
        trap_index = self.text.find("trap 'cleanup \"$?\"' EXIT")
        self.assertGreaterEqual(cleanup_index, 0)
        self.assertGreaterEqual(trap_index, 0)
        self.assertLess(cleanup_index, trap_index)

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

    def test_edit_action_serializes_host_probe_as_luau_literal_not_raw_json(self) -> None:
        self.assertIn("def to_luau_literal(value):", self.text)
        self.assertIn('host_probe_sample_luau = to_luau_literal(host_probe_sample)', self.text)
        self.assertIn('local hostProbeSample = """ + host_probe_sample_luau + """', self.text)
        self.assertNotIn('local hostProbeSample = """ + json.dumps(host_probe_sample, separators=(",", ":")) + """', self.text)

    def test_harness_captures_preview_telemetry_artifacts(self) -> None:
        self.assertIn("capture_preview_telemetry_artifacts()", self.text)
        self.assertIn('local preview_telemetry_dir="${ARNIS_PREVIEW_TELEMETRY_DIR:-/tmp}"', self.text)
        self.assertIn('curl -sf "$VSYNC_SERVER_URL/plugin/state"', self.text)
        self.assertIn('local plugin_state_json="$preview_telemetry_dir/arnis-preview-plugin-state.json"', self.text)
        self.assertIn('local telemetry_summary_txt="$preview_telemetry_dir/arnis-preview-telemetry-summary.txt"', self.text)
        self.assertIn("python3 -m scripts.preview_telemetry_summary", self.text)
        self.assertIn('log "preview telemetry saved: $plugin_state_json"', self.text)
        self.assertIn('log "preview telemetry summary: $(cat "$telemetry_summary_txt")"', self.text)

    def test_harness_does_not_ignore_vsync_plugin_install_failure(self) -> None:
        self.assertIn("ensure_vsync_plugin_installed()", self.text)
        self.assertNotIn("ensure_vsync_plugin_installed || true", self.text)
        self.assertIn("ensure_mcp_plugin_installed()", self.text)
        self.assertNotIn("ensure_mcp_plugin_installed || true", self.text)

    def test_vsync_repo_ownership_survives_prebuilt_binary_override(self) -> None:
        self.assertIn('if [[ -f "$VSYNC_REPO_DIR/Cargo.toml" ]] && command -v cargo >/dev/null 2>&1; then', self.text)
        self.assertIn('if [[ -n "$VSYNC_BINARY" && -x "$VSYNC_BINARY" ]]; then', self.text)
        repo_block_index = self.text.find('if [[ -f "$VSYNC_REPO_DIR/Cargo.toml" ]] && command -v cargo >/dev/null 2>&1; then')
        binary_fallback_index = self.text.find('if [[ -n "$VSYNC_BINARY" && -x "$VSYNC_BINARY" ]]; then\n    VSYNC_SOURCE_REPO=0')
        self.assertGreaterEqual(repo_block_index, 0)
        self.assertGreaterEqual(binary_fallback_index, 0)
        self.assertLess(repo_block_index, binary_fallback_index)
        self.assertIn('VSYNC_SOURCE_REPO=1', self.text)

    def test_mcp_plugin_is_bootstrapped_from_binary_on_clean_machine(self) -> None:
        self.assertIn('local installed_plugin="$ROBLOX_PLUGIN_DIR/MCPStudioPlugin.rbxm"', self.text)
        self.assertIn('log "installing MCP Studio plugin from $MCP_BINARY"', self.text)
        self.assertIn('"$MCP_BINARY" >/dev/null', self.text)
        enable_index = self.text.find("ensure_vsync_plugin_installed")
        mcp_index = self.text.find("ensure_mcp_plugin_installed")
        self.assertGreaterEqual(enable_index, 0)
        self.assertGreaterEqual(mcp_index, 0)
        self.assertLess(enable_index, mcp_index)

    def test_plugin_quarantine_is_file_level_not_directory_rename(self) -> None:
        self.assertIn("PLUGIN_SANDBOXED_FILES=()", self.text)
        self.assertIn('cp "$ROBLOX_PLUGIN_DIR/$plugin_name" "$sandbox_dir/$plugin_name"', self.text)
        self.assertIn('rm -f "$ROBLOX_PLUGIN_DIR/$plugin_name"', self.text)
        self.assertIn('for plugin_name in "${PLUGIN_SANDBOXED_FILES[@]}"; do', self.text)
        self.assertIn('cp "$PLUGIN_SANDBOX_DIR/$plugin_name" "$ROBLOX_PLUGIN_DIR/$plugin_name"', self.text)
        self.assertNotIn('mv "$ROBLOX_PLUGIN_DIR" "$sandbox_source_dir"', self.text)
        self.assertNotIn('mv "$PLUGIN_SANDBOX_SOURCE_DIR" "$ROBLOX_PLUGIN_DIR"', self.text)

    def test_screenshot_capture_failure_is_best_effort_only(self) -> None:
        self.assertIn('if screencapture -x "$target"; then', self.text)
        self.assertIn('log "failed to capture Studio screenshot: $target"', self.text)
        self.assertNotIn('screencapture -x "$target"\n  log "captured Studio screenshot: $target"', self.text)

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

    def test_isolated_preview_specs_gate_on_edit_sync_not_preview(self) -> None:
        self.assertIn('local edit_readiness_target="preview"', self.text)
        self.assertIn('if [[ -n "$RUNALL_SPEC_FILTER" ]]; then', self.text)
        self.assertIn('edit_readiness_target="edit_sync"', self.text)
        self.assertNotIn('if [[ -n "$RUNALL_SPEC_FILTER" && "$RUNALL_SPEC_FILTER" != *Preview* ]]; then', self.text)

    def test_harness_tracks_real_mcp_bridge_readiness_before_using_edit_actions(self) -> None:
        self.assertIn('MCP_READY_WAIT_SECONDS="${HARNESS_MCP_READY_WAIT_SECONDS:-12}"', self.text)
        self.assertIn('MCP_READY=1', self.text)
        self.assertIn('MCP_READY=0', self.text)
        self.assertIn('Studio MCP helper did not become ready after initial launch; edit-mode MCP actions will stay disabled', self.text)
        self.assertIn('Studio MCP helper did not become ready after relaunch; edit-mode MCP actions will stay disabled', self.text)
        self.assertIn('while [[ $waited -lt $MCP_READY_WAIT_SECONDS ]]; do', self.text)

    def test_wait_for_mcp_ready_requires_run_code_capability(self) -> None:
        match = re.search(
            r"wait_for_mcp_ready\(\) \{\n(?P<body>.*?)\n\}\n\nrun_edit_actions_via_runall_entry",
            self.text,
            re.DOTALL,
        )
        self.assertIsNotNone(match, "wait_for_mcp_ready function not found")
        body = match.group("body")
        self.assertIn('client.call_tool("get_studio_mode", {})', body)
        self.assertIn('"run_code",', body)
        self.assertIn("client_name='arnis-studio-harness-ready'", body)

    def test_harness_manages_mcp_plugin_installation(self) -> None:
        self.assertIn("ensure_mcp_plugin_installed()", self.text)
        self.assertIn("resolve_mcp_plugin_artifact()", self.text)
        self.assertIn('RBX_STUDIO_MCP_PLUGIN_PATH', self.text)
        self.assertIn('local installed_plugin="$ROBLOX_PLUGIN_DIR/MCPStudioPlugin.rbxm"', self.text)
        self.assertIn('local plugin_artifact=""', self.text)
        self.assertIn('plugin_artifact="$(resolve_mcp_plugin_artifact || true)"', self.text)
        self.assertIn('log "installing Roblox Studio MCP plugin from built artifact"', self.text)
        self.assertIn('"$MCP_BINARY" >/dev/null', self.text)
        self.assertIn('log "installing Roblox Studio MCP plugin via MCP binary installer"', self.text)
        self.assertIn('ensure_mcp_plugin_installed || {', self.text)

    def test_edit_mcp_path_skips_preview_probe_for_non_preview_isolated_specs(self) -> None:
        self.assertIn('do_play = os.environ.get("HARNESS_DO_PLAY", "0").strip().lower() in {"1", "true", "yes", "on"}', self.text)
        self.assertIn('run_preview_probe = (not do_play) and (runall_spec_filter == "" or "Preview" in runall_spec_filter)', self.text)
        self.assertIn("local runPreviewProbe = ", self.text)
        self.assertIn("if runPreviewProbe then", self.text)
        self.assertIn('status = "skipped"', self.text)
        self.assertIn('skipReason = "spec_filter_non_preview"', self.text)

    def test_shell_flow_skips_redundant_edit_probe_for_non_preview_isolated_specs(self) -> None:
        self.assertIn("should_run_edit_probe_best_effort()", self.text)
        self.assertIn('[[ -z "$RUNALL_SPEC_FILTER" ]]', self.text)
        self.assertIn('[[ "$RUNALL_SPEC_FILTER" == *Preview* ]]', self.text)
        self.assertIn('elif ! should_run_edit_probe_best_effort; then', self.text)
        self.assertIn('log "skipping redundant edit MCP probe for isolated non-preview spec"', self.text)

    def test_play_probe_avoids_full_scene_audit_in_play_mode(self) -> None:
        self.assertNotIn('emitSceneMarkers("ARNIS_SCENE_PLAY"', self.text)
        self.assertNotIn('SceneAudit.summarizeWorld(Workspace:FindFirstChild("GeneratedWorld_Austin"))', self.text)

    def test_play_probe_reports_world_root_candidates_and_counts(self) -> None:
        self.assertIn("local function summarizeWorldRoot(root)", self.text)
        self.assertIn('local generatedAustin = Workspace:FindFirstChild("GeneratedWorld_Austin")', self.text)
        self.assertIn('local generatedGeneric = Workspace:FindFirstChild("GeneratedWorld")', self.text)
        self.assertIn('generatedRoot = summarizeWorldRoot(generatedAustin or generatedGeneric)', self.text)
        self.assertIn('generatedAustin = summarizeWorldRoot(generatedAustin)', self.text)
        self.assertIn('generatedGeneric = summarizeWorldRoot(generatedGeneric)', self.text)
        self.assertIn('payload.austinStatus = Workspace:GetAttribute("VertigoAustinStatus")', self.text)
        self.assertIn('payload.austinManifestName = Workspace:GetAttribute("VertigoAustinManifestName")', self.text)
        self.assertIn('payload.austinWorldRootName = Workspace:GetAttribute("VertigoAustinWorldRootName")', self.text)
        self.assertIn('payload.austinWorldRootChildCount = Workspace:GetAttribute("VertigoAustinWorldRootChildCount")', self.text)
        self.assertIn('payload.austinWorldRootDescendantCount = Workspace:GetAttribute("VertigoAustinWorldRootDescendantCount")', self.text)
        self.assertIn('payload.bootstrapState = Workspace:GetAttribute("ArnisAustinBootstrapState")', self.text)
        self.assertIn('payload.bootstrapStateTrace = Workspace:GetAttribute("ArnisAustinBootstrapStateTrace")', self.text)
        self.assertIn('payload.bootstrapDuplicateCount = Workspace:GetAttribute("ArnisAustinBootstrapDuplicateCount")', self.text)
        self.assertIn('payload.bootstrapEntryCount = Workspace:GetAttribute("ArnisAustinBootstrapEntryCount")', self.text)
        self.assertIn('payload.bootstrapLastScriptPath = Workspace:GetAttribute("ArnisAustinBootstrapLastScriptPath")', self.text)

    def test_play_probe_captures_ordered_bootstrap_state_trace(self) -> None:
        self.assertIn('payload.bootstrapStateTrace = Workspace:GetAttribute("ArnisAustinBootstrapStateTrace")', self.text)
        self.assertIn("validate_play_bootstrap_trace()", self.text)
        self.assertIn('validate_play_bootstrap_trace "$ACTIVE_LOG"', self.text)
        self.assertIn('trace_text = payload.get("bootstrapStateTrace")', self.text)
        self.assertIn('duplicate_count = payload.get("bootstrapDuplicateCount")', self.text)
        self.assertIn('if duplicate_count not in (None, 0):', self.text)
        self.assertIn('"loading_manifest"', self.text)
        self.assertIn('"importing_startup"', self.text)
        self.assertIn('"world_ready"', self.text)
        self.assertIn('"streaming_ready"', self.text)
        self.assertIn('"minimap_ready"', self.text)
        self.assertIn('"gameplay_ready"', self.text)

    def test_play_probe_uses_json_objects_not_singleton_arrays(self) -> None:
        self.assertIn("local payload = {", self.text)
        self.assertNotIn("local payload = {{", self.text)
        self.assertIn("return {", self.text)
        self.assertNotIn("return {{", self.text)

    def test_play_probe_reports_streaming_residency_telemetry(self) -> None:
        self.assertIn('payload.streamingLoadedChunkCount = Workspace:GetAttribute("ArnisStreamingLoadedChunkCount")', self.text)
        self.assertIn('payload.streamingDesiredChunkCount = Workspace:GetAttribute("ArnisStreamingDesiredChunkCount")', self.text)
        self.assertIn('payload.streamingCandidateChunkCount = Workspace:GetAttribute("ArnisStreamingCandidateChunkCount")', self.text)
        self.assertIn('payload.streamingProcessedWorkItems = Workspace:GetAttribute("ArnisStreamingProcessedWorkItems")', self.text)
        self.assertIn('payload.streamingLastFocalX = Workspace:GetAttribute("ArnisStreamingLastFocalX")', self.text)
        self.assertIn('payload.streamingLastFocalZ = Workspace:GetAttribute("ArnisStreamingLastFocalZ")', self.text)

    def test_play_probe_reports_camera_and_humanoid_state(self) -> None:
        self.assertIn("local camera = Workspace.CurrentCamera", self.text)
        self.assertIn('local humanoid = character and character:FindFirstChildOfClass("Humanoid")', self.text)
        self.assertIn('cameraType = camera and tostring(camera.CameraType) or nil', self.text)
        self.assertIn('cameraSubject = camera and camera.CameraSubject and camera.CameraSubject:GetFullName() or nil', self.text)
        self.assertIn('cameraFocus = camera and vectorToTable(camera.Focus.Position) or nil', self.text)
        self.assertIn('cameraPosition = camera and vectorToTable(camera.CFrame.Position) or nil', self.text)
        self.assertIn('humanoidState = humanoid and tostring(humanoid:GetState()) or nil', self.text)
        self.assertIn('humanoidFloorMaterial = humanoid and tostring(humanoid.FloorMaterial) or nil', self.text)
        self.assertIn('humanoidHealth = humanoid and humanoid.Health or nil', self.text)
        self.assertIn('clientCameraType = player and player:GetAttribute("ArnisClientCameraType") or nil', self.text)
        self.assertIn('clientCameraSubject = player and player:GetAttribute("ArnisClientCameraSubject") or nil', self.text)
        self.assertIn('clientCameraSubjectClass = player and player:GetAttribute("ArnisClientCameraSubjectClass") or nil', self.text)
        self.assertIn('clientCameraMode = player and player:GetAttribute("ArnisClientCameraMode") or nil', self.text)
        self.assertIn('minimapEnabled = player and player:GetAttribute("ArnisMinimapEnabled") or nil', self.text)
        self.assertIn('minimapGuiReady = player and player:GetAttribute("ArnisMinimapGuiReady") or nil', self.text)
        self.assertIn('minimapWorldRootName = player and player:GetAttribute("ArnisMinimapWorldRootName") or nil', self.text)
        self.assertIn('minimapSnapshotCount = player and player:GetAttribute("ArnisMinimapSnapshotCount") or nil', self.text)
        self.assertIn('minimapFullscreen = player and player:GetAttribute("ArnisMinimapFullscreen") or nil', self.text)
        self.assertIn('minimapError = player and player:GetAttribute("ArnisMinimapError") or nil', self.text)
        self.assertIn('vehicleControllerReady = player and player:GetAttribute("ArnisVehicleControllerReady") or nil', self.text)
        self.assertIn("local function summarizeNearbyOverheadRoofParts(worldRoot, origin, excludeInstances)", self.text)
        self.assertIn("local function summarizeNearbyBuildingModels(worldRoot, origin)", self.text)
        self.assertIn('payload.nearbyOverheadRoofParts = summarizeNearbyOverheadRoofParts(', self.text)
        self.assertIn('payload.nearbyBuildingModels = summarizeNearbyBuildingModels(', self.text)

    def test_play_screenshot_is_captured_after_probe_settles(self) -> None:
        play_block = self.text.split('log "entering Play mode"', 1)[1]
        self.assertLess(
            play_block.index('run_probe_best_effort "play" 8'),
            play_block.index('capture_studio_screenshot "play"'),
        )

    def test_play_probe_keeps_play_session_alive_until_harness_capture(self) -> None:
        self.assertIn("play_probe_succeeded = False", self.text)
        self.assertIn("play_probe_succeeded = True", self.text)
        self.assertIn("if not play_probe_succeeded:", self.text)

    def test_play_probe_executes_inside_existing_play_session_without_auto_stop_tool(self) -> None:
        play_probe_block = re.search(
            r"run_play_probe_via_mcp\(\) \{\n(?P<body>.*?)\n\}\n\nlog_effective_play_camera_state",
            self.text,
            re.DOTALL,
        )
        self.assertIsNotNone(play_probe_block, "run_play_probe_via_mcp function not found")
        body = play_probe_block.group("body")
        self.assertIn("from studio_mcp_proxy_lib import build_mcp_client, run_code_in_play_session", body)
        self.assertIn("result = run_code_in_play_session(", body)
        self.assertIn('requested_mode="start_play"', body)
        self.assertNotIn('"run_script_in_play_mode"', body)

    def test_harness_treats_client_camera_marker_as_authoritative_play_signal(self) -> None:
        self.assertIn('log_effective_play_camera_state()', self.text)
        self.assertIn('rg -q "ARNIS_CLIENT_CAMERA " "$summary_source"', self.text)
        self.assertIn('grep -E "ARNIS_CLIENT_CAMERA " "$summary_source" | tail -n 1', self.text)
        self.assertIn('grep -E "ARNIS_MCP_PLAY_LATE |ARNIS_MCP_PLAY " "$summary_source" | tail -n 1', self.text)
        self.assertIn('play camera verdict (authoritative client):', self.text)
        self.assertIn('play camera verdict (server fallback):', self.text)
        self.assertIn('ARNIS_CLIENT_CAMERA|ARNIS_CLIENT_MINIMAP|ARNIS_MCP_PLAY|ARNIS_MCP_PLAY_LATE', self.text)

    def test_harness_treats_client_minimap_marker_as_authoritative_play_signal(self) -> None:
        self.assertIn('log_effective_play_minimap_state()', self.text)
        self.assertIn('rg -q "ARNIS_CLIENT_MINIMAP " "$summary_source"', self.text)
        self.assertIn('grep -E "ARNIS_CLIENT_MINIMAP " "$summary_source" | tail -n 1', self.text)
        self.assertIn('play minimap verdict (authoritative client):', self.text)
        self.assertIn('play minimap verdict (server fallback):', self.text)
        self.assertIn('ARNIS_CLIENT_MINIMAP|ARNIS_MCP_PLAY|ARNIS_MCP_PLAY_LATE', self.text)

    def test_harness_treats_client_world_marker_as_authoritative_play_signal(self) -> None:
        self.assertIn('log_effective_play_world_state()', self.text)
        self.assertIn('rg -q "ARNIS_CLIENT_WORLD " "$summary_source"', self.text)
        self.assertIn('grep -E "ARNIS_CLIENT_WORLD " "$summary_source" | tail -n 1', self.text)
        self.assertIn('play world verdict (authoritative client):', self.text)
        self.assertIn('play world verdict (server fallback):', self.text)
        self.assertIn('ARNIS_CLIENT_WORLD|ARNIS_CLIENT_CAMERA|ARNIS_CLIENT_MINIMAP|ARNIS_MCP_PLAY|ARNIS_MCP_PLAY_LATE', self.text)

    def test_play_probe_wall_timeout_exceeds_inner_mcp_budget(self) -> None:
        self.assertIn('local mcp_wall_timeout=$((PLAY_WAIT_SECONDS + 55))', self.text)
        self.assertIn('if [[ $mcp_wall_timeout -lt 100 ]]; then', self.text)
        self.assertIn('mcp_wall_timeout=100', self.text)
        self.assertIn('if [[ $mcp_wall_timeout -gt 150 ]]; then', self.text)
        self.assertIn('mcp_wall_timeout=150', self.text)
        self.assertIn('wall_clock_timeout = max(wait_seconds + 45, 90)', self.text)
        self.assertIn('timeout_seconds=max(wait_seconds + 35, 70)', self.text)

    def test_auto_built_clean_place_uses_one_canonical_output_path(self) -> None:
        self.assertIn('local output_place="$roblox_dir/out/arnis-test-clean-$output_suffix.rbxlx"', self.text)
        self.assertIn('local output_suffix="edit"', self.text)
        self.assertIn('output_suffix="play"', self.text)
        self.assertIn('elif [[ $RUNALL_EDIT_ENABLED -eq 1 ]]; then', self.text)
        self.assertIn('output_suffix="edit-tests"', self.text)
        self.assertIn('"$VSYNC_BINARY" --root "$roblox_dir" build --project "$build_project" --output "$output_place"', self.text)
        self.assertIn('printf \'%s\\n\' "$output_place"', self.text)
        self.assertIn(
            'if output_place="$(build_clean_place "$include_runtime_sample_data")"; then',
            self.text,
        )
        self.assertNotIn("--project out/default.build.project.json --output out/arnis-test-clean.rbxlx", self.text)
        self.assertNotIn('harness_project_args+=(--include-canonical-sample-data)', self.text)

    def test_edit_only_auto_build_omits_runtime_sample_data_from_clean_place(self) -> None:
        self.assertIn('local include_runtime_sample_data="${1:-true}"', self.text)
        self.assertIn('python3 "$ROOT_DIR/scripts/generate_harness_projects.py" "${harness_project_args[@]}"', self.text)
        self.assertIn('harness_project_args+=(--include-runtime-sample-data)', self.text)
        self.assertIn('if [[ $DO_PLAY -eq 0 ]]; then', self.text)
        self.assertIn('include_runtime_sample_data="false"', self.text)
        self.assertNotIn('harness_project_args+=(--include-canonical-sample-data)', self.text)

    def test_edit_test_builds_keep_bounded_canonical_sample_data_visible(self) -> None:
        self.assertIn('elif [[ $RUNALL_EDIT_ENABLED -eq 1 ]]; then', self.text)
        self.assertIn('output_suffix="edit-tests"', self.text)

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

    def test_play_probe_captures_bootstrap_attempt_identity_and_trace(self) -> None:
        self.assertIn('payload.bootstrapState = Workspace:GetAttribute("ArnisAustinBootstrapState")', self.text)
        self.assertIn('payload.bootstrapAttemptId = Workspace:GetAttribute("ArnisAustinBootstrapAttemptId")', self.text)
        self.assertIn('payload.bootstrapStateTrace = Workspace:GetAttribute("ArnisAustinBootstrapStateTrace")', self.text)
        self.assertIn('payload.bootstrapDuplicateCount = Workspace:GetAttribute("ArnisAustinBootstrapDuplicateCount")', self.text)


if __name__ == "__main__":
    unittest.main()

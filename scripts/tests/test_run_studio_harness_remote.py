#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
REMOTE_HARNESS_PATH = ROOT / "scripts" / "run_studio_harness_remote.sh"


class RunStudioHarnessRemoteTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.text = REMOTE_HARNESS_PATH.read_text(encoding="utf-8")

    def test_uses_profile_based_remote_configuration_without_baked_host_defaults(self) -> None:
        self.assertIn('REMOTE_PROFILE="${ARNIS_REMOTE_STUDIO_PROFILE:-primary}"', self.text)
        self.assertIn('LOCAL_REMOTE_CONFIG="$ROOT_DIR/scripts/remote_studio_profiles.local.sh"', self.text)
        self.assertIn('EXAMPLE_REMOTE_CONFIG="$ROOT_DIR/scripts/remote_studio_profiles.example.sh"', self.text)
        self.assertIn('resolve_profile_value', self.text)
        self.assertNotIn('primary.local', self.text)
        self.assertNotIn('/Users/adpena/Projects/.codex-remote-studio', self.text)

    def test_syncs_local_arnis_and_vsync_snapshots_to_remote_stage(self) -> None:
        self.assertIn('LOCAL_ARNIS_DIR="$ROOT_DIR"', self.text)
        self.assertIn('git -C "$ROOT_DIR" rev-parse --git-common-dir', self.text)
        self.assertIn('LOCAL_VSYNC_DIR="${VSYNC_REPO_DIR:-$DEFAULT_VSYNC_DIR}"', self.text)
        self.assertIn("render_rsync_remote_path()", self.text)
        self.assertIn('RSYNC_REMOTE_ARNIS_DIR="$(render_rsync_remote_path "$REMOTE_ARNIS_DIR")"', self.text)
        self.assertIn('RSYNC_REMOTE_VSYNC_DIR="$(render_rsync_remote_path "$REMOTE_VSYNC_DIR")"', self.text)
        self.assertIn('sync_repo_snapshot "$LOCAL_ARNIS_DIR" "$REMOTE_ARNIS_DIR" "$RSYNC_REMOTE_ARNIS_DIR"', self.text)
        self.assertIn('sync_repo_snapshot "$LOCAL_VSYNC_DIR" "$REMOTE_VSYNC_DIR" "$RSYNC_REMOTE_VSYNC_DIR"', self.text)
        self.assertIn('git -C "$repo_dir" ls-files -z --cached --others --exclude-standard', self.text)
        self.assertIn('rsync -a --from0 --files-from="$manifest"', self.text)
        self.assertIn('reset_remote_stage_dir "$remote_dir"', self.text)
        self.assertIn('if git -C "$source_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then', self.text)

    def test_remote_seed_prefers_existing_remote_repos_when_present(self) -> None:
        self.assertIn('REMOTE_ARNIS_BASE="$(resolve_profile_value ARNIS_REMOTE_STUDIO_BASE_ARNIS', self.text)
        self.assertIn('REMOTE_VSYNC_BASE="$(resolve_profile_value ARNIS_REMOTE_STUDIO_BASE_VSYNC', self.text)
        self.assertIn('seed_stage "$remote_arnis_base" "$remote_arnis_dir"', self.text)
        self.assertIn('seed_stage "$remote_vsync_base" "$remote_vsync_dir"', self.text)
        self.assertIn('git -C "$source_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1', self.text)

    def test_remote_seed_supports_cold_remote_bootstrap_without_seed_repos(self) -> None:
        self.assertIn('if [[ ! -d "$source_dir" ]]; then', self.text)
        self.assertIn('return 0', self.text)

    def test_no_sync_requires_existing_remote_stage_with_clear_validation(self) -> None:
        self.assertIn('ensure_remote_stage_ready()', self.text)
        self.assertIn('missing remote arnis stage', self.text)
        self.assertIn('missing remote vertigo-sync stage', self.text)
        self.assertIn('re-run without --no-sync', self.text)

    def test_runs_same_remote_harness_with_remote_vsync_binary(self) -> None:
        self.assertIn('needs_vsync_build()', self.text)
        self.assertIn('if needs_vsync_build "$remote_vsync_dir" "$remote_vsync_target_dir"; then', self.text)
        self.assertIn('CARGO_TARGET_DIR="$remote_vsync_target_dir"', self.text)
        self.assertIn('cargo build --manifest-path "$remote_vsync_dir/Cargo.toml" --bin vsync >/dev/null', self.text)
        self.assertIn('cd "$remote_arnis_dir"', self.text)
        self.assertIn('VSYNC_REPO_DIR="$remote_vsync_dir"', self.text)
        self.assertIn('VSYNC_BIN="$remote_vsync_target_dir/debug/vsync"', self.text)
        self.assertIn('bash scripts/run_studio_harness.sh "$@"', self.text)

    def test_fetches_remote_logs_and_screenshots_back_locally(self) -> None:
        self.assertIn('LOCAL_ARTIFACT_DIR="${ARNIS_REMOTE_STUDIO_ARTIFACT_DIR:-/tmp/arnis-remote-studio}"', self.text)
        self.assertIn('remote_latest_log="$(ssh "$REMOTE_HOST" ', self.text)
        self.assertIn('rsync -a "$REMOTE_HOST:$remote_latest_log" "$LOCAL_ARTIFACT_DIR/"', self.text)
        self.assertIn('/tmp/arnis-studio-harness-edit.png', self.text)
        self.assertIn('/tmp/arnis-studio-harness-play.png', self.text)
        self.assertIn('/tmp/arnis-preview-plugin-state.json', self.text)

    def test_supports_remote_profile_host_and_root_flags(self) -> None:
        self.assertIn('--remote-profile PROFILE', self.text)
        self.assertIn('--remote-host HOST', self.text)
        self.assertIn('--remote-root PATH', self.text)
        self.assertIn('--no-sync', self.text)

    def test_example_profile_template_exists(self) -> None:
        template_path = ROOT / "scripts" / "remote_studio_profiles.example.sh"
        self.assertTrue(template_path.exists(), "expected remote studio profile example template")
        template_text = template_path.read_text(encoding="utf-8")
        self.assertIn("ARNIS_REMOTE_STUDIO_HOST_PRIMARY", template_text)
        self.assertIn("ARNIS_REMOTE_STUDIO_HOST_TERTIARY", template_text)
        self.assertNotIn("primary.local", template_text)
        self.assertNotIn("tertiary.local", template_text)

    def test_remote_studio_docs_keep_profiles_generic_and_cover_cold_start_bootstrap(self) -> None:
        docs_text = (ROOT / "docs" / "remote-studio-development.md").read_text(encoding="utf-8")
        self.assertIn("Direct Development On The Active Dev Machine", docs_text)
        self.assertIn("Fresh remote machines do not need pre-seeded sibling clones", docs_text)
        self.assertIn("tracked files and untracked non-ignored files", docs_text)
        self.assertIn("profile aliases", docs_text)
        self.assertNotIn("primary.local", docs_text)
        self.assertNotIn("tertiary.local", docs_text)

    def test_gitignore_blocks_generated_artifacts_from_git_aware_sync(self) -> None:
        arnis_gitignore = (ROOT / ".gitignore").read_text(encoding="utf-8")
        vertigo_sync_gitignore = (ROOT.parent / "vertigo-sync" / ".gitignore").read_text(encoding="utf-8")
        for text in (arnis_gitignore, vertigo_sync_gitignore):
            with self.subTest(gitignore=text[:32]):
                self.assertTrue("**/target/" in text or "**/target" in text)
                self.assertIn("**/out/", text)
                self.assertIn("**/build/", text)
                self.assertIn("**/dist/", text)
                self.assertIn("**/.venv/", text)
                self.assertIn("**/node_modules/", text)


if __name__ == "__main__":
    unittest.main()

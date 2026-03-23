from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "scripts" / "studio_harness_policy.py"


def load_module():
    spec = importlib.util.spec_from_file_location("studio_harness_policy", MODULE_PATH)
    if spec is None or spec.loader is None:
        raise AssertionError(f"failed to load module spec from {MODULE_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class StudioHarnessPolicyTests(unittest.TestCase):
    def test_cleanup_closes_owned_studio_after_success(self) -> None:
        mod = load_module()
        decision = mod.decide_cleanup_close(
            exit_code=0,
            close_on_exit=True,
            harness_owns_studio=True,
            session_status="ready_edit",
        )
        self.assertTrue(decision["should_close"])
        self.assertEqual(decision["reason"], "success")

    def test_cleanup_preserves_owned_studio_after_failure(self) -> None:
        mod = load_module()
        decision = mod.decide_cleanup_close(
            exit_code=1,
            close_on_exit=True,
            harness_owns_studio=True,
            session_status="ready_edit",
        )
        self.assertFalse(decision["should_close"])
        self.assertEqual(decision["reason"], "failed_run")

    def test_cleanup_preserves_blocked_dialog_session(self) -> None:
        mod = load_module()
        decision = mod.decide_cleanup_close(
            exit_code=0,
            close_on_exit=True,
            harness_owns_studio=True,
            session_status="blocked_dialog",
        )
        self.assertFalse(decision["should_close"])
        self.assertEqual(decision["reason"], "blocked_dialog")

    def test_stop_play_only_when_session_or_log_says_playing(self) -> None:
        mod = load_module()
        self.assertFalse(
            mod.should_stop_play_before_quit(
                session_status="ready_edit",
                log_indicates_play=False,
            )
        )
        self.assertTrue(
            mod.should_stop_play_before_quit(
                session_status="ready_play",
                log_indicates_play=False,
            )
        )
        self.assertTrue(
            mod.should_stop_play_before_quit(
                session_status="ready_edit",
                log_indicates_play=True,
            )
        )

    def test_graceful_quit_waits_for_play_to_end(self) -> None:
        mod = load_module()
        self.assertFalse(mod.should_send_graceful_quit("ready_play"))
        self.assertFalse(mod.should_send_graceful_quit("transitioning"))
        self.assertTrue(mod.should_send_graceful_quit("ready_edit"))
        self.assertTrue(mod.should_send_graceful_quit("blocked_dialog"))

    def test_mcp_stop_is_ignored_when_ui_and_log_say_edit(self) -> None:
        mod = load_module()
        self.assertTrue(
            mod.should_ignore_mcp_stop(
                mode_label="stop",
                session_status="ready_edit",
                log_indicates_play=False,
            )
        )
        self.assertFalse(
            mod.should_ignore_mcp_stop(
                mode_label="stop",
                session_status="ready_play",
                log_indicates_play=False,
            )
        )
        self.assertTrue(
            mod.should_ignore_mcp_stop(
                mode_label="stop",
                session_status="unknown",
                log_indicates_play=False,
            )
        )
        self.assertFalse(
            mod.should_ignore_mcp_stop(
                mode_label="edit",
                session_status="ready_edit",
                log_indicates_play=False,
            )
        )

    def test_mcp_stop_override_payload_can_be_computed_without_bash(self) -> None:
        mod = load_module()
        decision = mod.mcp_mode_stop_decision(
            mode_label="stop",
            session_status="unknown",
            log_indicates_play=False,
        )
        self.assertEqual(decision, "ignore")
        decision = mod.mcp_mode_stop_decision(
            mode_label="stop",
            session_status="ready_play",
            log_indicates_play=False,
        )
        self.assertEqual(decision, "respect")
        decision = mod.mcp_mode_stop_decision(
            mode_label="edit",
            session_status="ready_edit",
            log_indicates_play=False,
        )
        self.assertEqual(decision, "not_applicable")

    def test_edit_action_payload_success_requires_clean_runall_and_preview(self) -> None:
        mod = load_module()
        self.assertTrue(
            mod.is_successful_edit_action_payload(
                {
                    "errors": [],
                    "runAll": {"failed": 0, "passed": 55},
                    "preview": {"status": "ok"},
                }
            )
        )
        self.assertFalse(
            mod.is_successful_edit_action_payload(
                {
                    "errors": ["AustinPreviewBuilder: failed"],
                    "runAll": {"failed": 0},
                    "preview": {"status": "ok"},
                }
            )
        )
        self.assertFalse(
            mod.is_successful_edit_action_payload(
                {
                    "errors": [],
                    "runAll": {"failed": 1},
                    "preview": {"status": "ok"},
                }
            )
        )
        self.assertFalse(
            mod.is_successful_edit_action_payload(
                {
                    "errors": [],
                    "runAll": {"failed": 0},
                    "preview": {"status": "timeout"},
                }
            )
        )


if __name__ == "__main__":
    unittest.main()

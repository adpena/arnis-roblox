from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = ROOT / "scripts" / "studio_ui_control.py"


def load_module():
    spec = importlib.util.spec_from_file_location("studio_ui_control", MODULE_PATH)
    if spec is None or spec.loader is None:
        raise AssertionError(f"failed to load module spec from {MODULE_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class StudioUiControlTests(unittest.TestCase):
    def test_infer_state_label_uses_enabled_stop_item_for_playing(self) -> None:
        mod = load_module()
        state = mod.infer_state_label(
            {
                "front_window": "place.rbxlx - Roblox Studio",
                "has_test_menu": True,
                "has_stop_menu_item": True,
                "has_stop_menu_item_enabled": True,
                "button_names": [],
                "window_count": 1,
                "has_file_menu": True,
            }
        )
        self.assertEqual(state, "playing")

    def test_infer_state_label_treats_disabled_stop_item_as_editor_ready(self) -> None:
        mod = load_module()
        state = mod.infer_state_label(
            {
                "front_window": "place.rbxlx - Roblox Studio",
                "has_test_menu": True,
                "has_stop_menu_item": True,
                "has_stop_menu_item_enabled": False,
                "button_names": [],
                "window_count": 1,
                "has_file_menu": True,
            }
        )
        self.assertEqual(state, "editor_ready")

    def test_classify_session_status_not_running(self) -> None:
        mod = load_module()
        status = mod.classify_session_status(
            {
                "state": "not_running",
                "front_window": "",
                "window_count": 0,
            },
            0,
        )
        self.assertEqual(status["status"], "not_running")
        self.assertTrue(status["safe_to_open"])
        self.assertFalse(status["safe_to_quit"])

    def test_classify_session_status_editor_ready(self) -> None:
        mod = load_module()
        status = mod.classify_session_status(
            {
                "state": "editor_ready",
                "front_window": "place.rbxlx - Roblox Studio",
                "window_count": 1,
            },
            1,
        )
        self.assertEqual(status["status"], "ready_edit")
        self.assertTrue(status["ready_for_menu"])
        self.assertTrue(status["ready_for_harness"])

    def test_classify_session_status_playing(self) -> None:
        mod = load_module()
        status = mod.classify_session_status(
            {
                "state": "playing",
                "front_window": "place.rbxlx - Roblox Studio",
                "window_count": 1,
            },
            1,
        )
        self.assertEqual(status["status"], "ready_play")
        self.assertTrue(status["ready_play"])
        self.assertTrue(status["safe_to_open"])

    def test_classify_session_status_dialog_blocked(self) -> None:
        mod = load_module()
        status = mod.classify_session_status(
            {
                "state": "save_prompt",
                "front_window": "Do you want to save",
                "window_count": 1,
            },
            1,
        )
        self.assertEqual(status["status"], "blocked_dialog")
        self.assertTrue(status["blocked_dialog"])
        self.assertFalse(status["ready_for_harness"])

    def test_classify_session_status_file_panel_blocked(self) -> None:
        mod = load_module()
        status = mod.classify_session_status(
            {
                "state": "menu_ready",
                "front_window": "Open Roblox File",
                "window_count": 3,
            },
            1,
        )
        self.assertEqual(status["status"], "blocked_dialog")
        self.assertTrue(status["blocked_dialog"])
        self.assertFalse(status["ready_for_harness"])

    def test_classify_session_status_lighting_migration_blocked(self) -> None:
        mod = load_module()
        status = mod.classify_session_status(
            {
                "state": "menu_ready",
                "front_window": "Lighting Technology Migration",
                "window_count": 2,
            },
            1,
        )
        self.assertEqual(status["status"], "blocked_dialog")
        self.assertTrue(status["blocked_dialog"])
        self.assertFalse(status["ready_for_harness"])

    def test_classify_session_status_save_close_blocked(self) -> None:
        mod = load_module()
        status = mod.classify_session_status(
            {
                "state": "menu_ready",
                "front_window": "Do you want to save changes before closing?",
                "window_count": 2,
            },
            1,
        )
        self.assertEqual(status["status"], "blocked_dialog")
        self.assertTrue(status["blocked_dialog"])
        self.assertFalse(status["ready_for_harness"])

    def test_classify_session_status_transitioning(self) -> None:
        mod = load_module()
        status = mod.classify_session_status(
            {
                "state": "window_open",
                "front_window": "Roblox Studio",
                "window_count": 1,
            },
            1,
        )
        self.assertEqual(status["status"], "transitioning")
        self.assertTrue(status["transitioning"])
        self.assertFalse(status["ready_for_harness"])


if __name__ == "__main__":
    unittest.main()

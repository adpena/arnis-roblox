#!/usr/bin/env python3
from __future__ import annotations

import unittest

from scripts.preview_telemetry_summary import summarize_plugin_state


class PreviewTelemetrySummaryTests(unittest.TestCase):
    def test_summarize_plugin_state_prefers_snapshot_counters_when_present(self) -> None:
        payload = {
            "preview_runtime": {
                "studio_connected": True,
                "plugin_attached": True,
                "project_loaded": True,
                "sync_status": "connected",
                "connection": {"ws_connected": True},
            },
            "preview_project": {
                "preview": {
                    "build_active": False,
                    "state_apply_pending": False,
                    "sync_state": "idle",
                },
                "full_bake": {"active": False, "last_result": None},
            },
            "preview_project_snapshot": {
                "counters": {
                    "build_scheduled": 1,
                    "sync_complete": 1,
                    "sync_cancelled": 0,
                    "state_apply_succeeded": 1,
                    "state_apply_failed": 0,
                },
                "chunkTotals": {"imported": 52, "skipped": 0, "unloaded": 0},
            },
        }

        self.assertEqual(
            summarize_plugin_state(payload),
            "runtime=connected=1 attached=1 project_loaded=1 sync_status=connected ws_connected=1; "
            "project=sync_state=idle build_active=0 state_apply_pending=0 full_bake_active=0 "
            "build=1 sync_complete=1 sync_cancelled=0 state_apply_succeeded=1 state_apply_failed=0 "
            "imported=52 skipped=0 unloaded=0",
        )

    def test_summarize_plugin_state_falls_back_to_compact_project_facts(self) -> None:
        payload = {
            "preview_runtime": {
                "studio_connected": True,
                "plugin_attached": True,
                "project_loaded": False,
                "sync_status": "connecting",
                "connection": {"ws_connected": False},
            },
            "preview_project": {
                "preview": {
                    "build_active": True,
                    "state_apply_pending": True,
                    "sync_state": "syncing",
                },
                "full_bake": {"active": True, "last_result": "pending"},
            },
        }

        self.assertEqual(
            summarize_plugin_state(payload),
            "runtime=connected=1 attached=1 project_loaded=0 sync_status=connecting ws_connected=0; "
            "project=sync_state=syncing build_active=1 state_apply_pending=1 full_bake_active=1 "
            "full_bake_last_result=pending",
        )


if __name__ == "__main__":
    unittest.main()

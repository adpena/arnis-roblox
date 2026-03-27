#!/usr/bin/env python3
from __future__ import annotations

import io
import json
from urllib.error import HTTPError
from unittest import mock
import unittest

from scripts import studio_harness_policy


class StudioHarnessPolicyTests(unittest.TestCase):
    def test_fetch_readiness_uses_authoritative_readiness_endpoint(self) -> None:
        response = io.BytesIO(
            json.dumps(
                {
                    "target": "edit_sync",
                    "ready": True,
                    "epoch": 7,
                    "incarnation_id": "inc-7",
                    "status_class": "ready",
                    "code": "ready",
                    "reason": None,
                }
            ).encode("utf-8")
        )
        with mock.patch("scripts.studio_harness_policy.request.urlopen", return_value=response) as urlopen:
            payload = studio_harness_policy.fetch_readiness("http://127.0.0.1:7575", "edit_sync")

        self.assertEqual(payload["target"], "edit_sync")
        self.assertTrue(payload["ready"])
        self.assertEqual(payload["epoch"], 7)
        self.assertEqual(payload["incarnation_id"], "inc-7")
        urlopen.assert_called_once()
        self.assertEqual(urlopen.call_args.args[0], "http://127.0.0.1:7575/readiness?target=edit_sync")

    def test_wait_for_readiness_retries_until_authoritative_record_is_ready(self) -> None:
        stale = io.BytesIO(
            json.dumps(
                {
                    "target": "edit_sync",
                    "ready": False,
                    "epoch": 7,
                    "incarnation_id": "inc-7",
                    "status_class": "blocked",
                    "code": "snapshot_reconciling",
                    "reason": "snapshot_reconciling",
                }
            ).encode("utf-8")
        )
        ready = io.BytesIO(
            json.dumps(
                {
                    "target": "edit_sync",
                    "ready": True,
                    "epoch": 8,
                    "incarnation_id": "inc-7",
                    "status_class": "ready",
                    "code": "ready",
                    "reason": None,
                }
            ).encode("utf-8")
        )
        with (
            mock.patch(
                "scripts.studio_harness_policy.request.urlopen",
                side_effect=[stale, ready],
            ),
            mock.patch("scripts.studio_harness_policy.time.sleep"),
        ):
            payload = studio_harness_policy.wait_for_readiness(
                "http://127.0.0.1:7575",
                "edit_sync",
                2,
            )

        self.assertEqual(payload["target"], "edit_sync")
        self.assertTrue(payload["ready"])
        self.assertEqual(payload["epoch"], 8)
        self.assertEqual(payload["incarnation_id"], "inc-7")

    def test_wait_for_readiness_times_out_after_404_readiness_endpoint(self) -> None:
        error = HTTPError(
            url="http://127.0.0.1:7575/readiness?target=preview",
            code=404,
            msg="Not Found",
            hdrs=None,
            fp=None,
        )
        with (
            mock.patch(
                "scripts.studio_harness_policy.request.urlopen",
                side_effect=error,
            ),
            mock.patch("scripts.studio_harness_policy.time.sleep"),
        ):
            with self.assertRaises(TimeoutError) as ctx:
                studio_harness_policy.wait_for_readiness(
                    "http://127.0.0.1:7575",
                    "preview",
                    1,
                )

        self.assertIn("/readiness?target=preview", str(ctx.exception))
        self.assertIn("HTTP Error 404", str(ctx.exception))

    def test_build_readiness_expectation_uses_target_epoch_and_incarnation(self) -> None:
        expectation = studio_harness_policy.build_readiness_expectation(
            {
                "target": "preview",
                "ready": True,
                "epoch": 42,
                "incarnation_id": "inc-42",
                "status_class": "ready",
                "code": "ready",
                "reason": None,
            }
        )

        self.assertEqual(expectation["expected_target"], "preview")
        self.assertEqual(expectation["expected_epoch"], 42)
        self.assertEqual(expectation["expected_incarnation_id"], "inc-42")


if __name__ == "__main__":
    unittest.main()

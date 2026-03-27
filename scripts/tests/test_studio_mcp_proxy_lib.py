#!/usr/bin/env python3
from __future__ import annotations

import unittest

from scripts.studio_mcp_proxy_lib import ensure_play_mode, run_code_in_play_session


class FakeClient:
    def __init__(self, initial_mode: str) -> None:
        self.mode = initial_mode
        self.calls: list[tuple[str, dict, bool, int | None]] = []

    def call_tool(
        self,
        name: str,
        arguments: dict | None = None,
        *,
        allow_is_error: bool = False,
        timeout_seconds: int | None = None,
    ) -> dict:
        args = arguments or {}
        self.calls.append((name, args, allow_is_error, timeout_seconds))
        if name == "get_studio_mode":
            return {"content": [{"type": "text", "text": self.mode}]}
        if name == "start_stop_play":
            requested = args.get("mode", "start_play")
            if requested == "stop":
                self.mode = "stop"
            else:
                self.mode = requested
            return {"content": [{"type": "text", "text": "ok"}]}
        if name == "run_code":
            return {"content": [{"type": "text", "text": "ok"}], "isError": False}
        raise AssertionError(f"unexpected tool {name}")


class StudioMcpProxyLibTests(unittest.TestCase):
    def test_ensure_play_mode_starts_play_when_stopped(self) -> None:
        client = FakeClient(initial_mode="stop")

        ensure_play_mode(client, requested_mode="start_play")

        self.assertEqual(client.mode, "start_play")
        self.assertEqual(client.calls[0][0], "get_studio_mode")
        self.assertEqual(client.calls[1][0], "start_stop_play")
        self.assertEqual(client.calls[1][1], {"mode": "start_play"})

    def test_run_code_in_play_session_uses_run_code_not_auto_stop_tool(self) -> None:
        client = FakeClient(initial_mode="start_play")

        result = run_code_in_play_session(
            client,
            "print('hello')",
            requested_mode="start_play",
            timeout_seconds=77,
        )

        self.assertEqual(result["content"][0]["text"], "ok")
        tool_names = [call[0] for call in client.calls]
        self.assertEqual(tool_names, ["get_studio_mode", "run_code"])
        self.assertEqual(client.calls[-1][1], {"command": "print('hello')"})
        self.assertEqual(client.calls[-1][3], 77)


if __name__ == "__main__":
    unittest.main()

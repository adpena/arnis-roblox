#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import urllib.request
import uuid
from typing import Any


class ProbeError(RuntimeError):
    pass


def collect_strings(value: Any) -> list[str]:
    strings: list[str] = []

    def _walk(node: Any) -> None:
        if isinstance(node, str):
            strings.append(node)
            return
        if isinstance(node, bool):
            strings.append("true" if node else "false")
            return
        if isinstance(node, (int, float)):
            strings.append(str(node))
            return
        if isinstance(node, dict):
            for nested in node.values():
                _walk(nested)
            return
        if isinstance(node, list):
            for nested in node:
                _walk(nested)

    _walk(value)
    return strings


def best_mode_from_payload(payload: Any) -> str | None:
    for text in collect_strings(payload):
        candidate = text.strip()
        if candidate in {"stop", "start_play", "run_server"}:
            return candidate
    return None


def ensure_play_mode(
    client: Any,
    *,
    requested_mode: str = "start_play",
    allow_is_error: bool = True,
) -> str:
    current_mode = best_mode_from_payload(client.call_tool("get_studio_mode", {}))
    if current_mode != requested_mode:
        client.call_tool(
            "start_stop_play",
            {"mode": requested_mode},
            allow_is_error=allow_is_error,
        )
        current_mode = requested_mode
    return current_mode or requested_mode


def run_code_in_play_session(
    client: Any,
    command: str,
    *,
    requested_mode: str = "start_play",
    allow_is_error: bool = True,
    timeout_seconds: int | None = None,
) -> Any:
    ensure_play_mode(client, requested_mode=requested_mode, allow_is_error=allow_is_error)
    return client.call_tool(
        "run_code",
        {"command": command},
        allow_is_error=allow_is_error,
        timeout_seconds=timeout_seconds,
    )


class HttpProxyClient:
    def __init__(self, proxy_url: str, timeout_seconds: int) -> None:
        self._proxy_url = proxy_url
        self._timeout_seconds = timeout_seconds

    def close(self) -> None:
        return None

    def initialize(self) -> None:
        return None

    def call_tool(
        self,
        name: str,
        arguments: dict[str, Any] | None = None,
        *,
        allow_is_error: bool = False,
        timeout_seconds: int | None = None,
    ) -> Any:
        variant_name = {
            "run_code": "RunCode",
            "insert_model": "InsertModel",
            "get_console_output": "GetConsoleOutput",
            "start_stop_play": "StartStopPlay",
            "run_script_in_play_mode": "RunScriptInPlayMode",
            "get_studio_mode": "GetStudioMode",
        }.get(name)
        if variant_name is None:
            raise ProbeError(f"unsupported MCP proxy tool: {name}")

        payload = {
            "id": str(uuid.uuid4()),
            "args": {
                variant_name: arguments or {},
            },
        }
        data = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        request = urllib.request.Request(
            self._proxy_url,
            data=data,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        timeout = timeout_seconds if timeout_seconds is not None else self._timeout_seconds
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                body = json.loads(response.read().decode("utf-8"))
        except Exception as exc:  # pragma: no cover - surfaced in harness logs
            raise ProbeError(f"MCP proxy request failed for {name}: {exc}") from exc

        success = bool(body.get("success"))
        result = {
            "content": [{"type": "text", "text": str(body.get("response", ""))}],
            "isError": not success,
        }
        if result["isError"] and not allow_is_error:
            raise ProbeError(f"MCP proxy tool '{name}' returned isError=true: {result}")
        return result


def build_mcp_client(
    direct_client_cls: type[Any],
    *,
    mcp_bin: str,
    timeout_seconds: int,
    protocol_version: str,
    client_name: str,
) -> Any:
    proxy_url = os.environ.get("MCP_PROXY_URL", "").strip()
    if proxy_url:
        return HttpProxyClient(proxy_url, timeout_seconds=timeout_seconds)
    return direct_client_cls(
        mcp_bin,
        timeout_seconds=timeout_seconds,
        protocol_version=protocol_version,
        client_name=client_name,
    )

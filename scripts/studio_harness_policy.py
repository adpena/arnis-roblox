#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import time
import sys
from urllib import request


READINESS_TARGETS = {"edit_sync", "preview", "full_bake_start", "full_bake_result"}


def should_stop_play_before_quit(session_status: str, log_indicates_play: bool) -> bool:
    return session_status == "ready_play" or log_indicates_play


def should_send_graceful_quit(session_status: str) -> bool:
    return session_status not in {"ready_play", "transitioning"}


def should_ignore_mcp_stop(mode_label: str, session_status: str, log_indicates_play: bool) -> bool:
    return mode_label == "stop" and session_status != "ready_play" and not log_indicates_play


def mcp_mode_stop_decision(mode_label: str, session_status: str, log_indicates_play: bool) -> str:
    if mode_label != "stop":
        return "not_applicable"
    if should_ignore_mcp_stop(mode_label, session_status, log_indicates_play):
        return "ignore"
    return "respect"


def is_successful_edit_action_payload(payload: object) -> bool:
    if not isinstance(payload, dict):
        return False
    errors = payload.get("errors")
    if isinstance(errors, list) and errors:
        return False
    run_all = payload.get("runAll")
    if isinstance(run_all, dict):
        failed = run_all.get("failed")
        if isinstance(failed, (int, float)) and failed != 0:
            return False
    preview = payload.get("preview")
    if isinstance(preview, dict):
        status = preview.get("status")
        if isinstance(status, str) and status not in {"ok"}:
            return False
    return True


def decide_cleanup_close(
    *,
    exit_code: int,
    close_on_exit: bool,
    harness_owns_studio: bool,
    session_status: str,
) -> dict[str, object]:
    if not close_on_exit:
        return {"should_close": False, "reason": "disabled"}
    if not harness_owns_studio:
        return {"should_close": False, "reason": "not_owned"}
    if exit_code != 0:
        return {"should_close": False, "reason": "failed_run"}
    if session_status == "blocked_dialog":
        return {"should_close": False, "reason": "blocked_dialog"}
    if session_status == "transitioning":
        return {"should_close": False, "reason": "transitioning"}
    return {"should_close": True, "reason": "success"}


def parse_bool_flag(raw: str) -> bool:
    normalized = raw.strip().lower()
    return normalized in {"1", "true", "yes", "on"}


def normalize_readiness_target(target: str) -> str:
    normalized = target.strip().lower()
    if normalized not in READINESS_TARGETS:
        raise ValueError(
            "invalid readiness target: "
            f"{target}. Expected one of: {', '.join(sorted(READINESS_TARGETS))}"
        )
    return normalized


def fetch_readiness(base_url: str, target: str) -> dict[str, object]:
    readiness_target = normalize_readiness_target(target)
    url = f"{base_url.rstrip('/')}/readiness?target={readiness_target}"
    with request.urlopen(url, timeout=10) as response:
        payload = json.load(response)
    if not isinstance(payload, dict):
        raise ValueError("readiness response must be a JSON object")
    return payload


def wait_for_readiness(base_url: str, target: str, timeout_seconds: int) -> dict[str, object]:
    readiness_target = normalize_readiness_target(target)
    deadline = time.monotonic() + max(timeout_seconds, 0)
    last_error: Exception | None = None

    while time.monotonic() < deadline:
        try:
            payload = fetch_readiness(base_url, readiness_target)
            if payload.get("target") != readiness_target:
                raise ValueError(
                    "readiness response target mismatch: "
                    f"expected {readiness_target}, got {payload.get('target')!r}"
                )
            if payload.get("ready") is True:
                return payload
            last_error = None
        except Exception as exc:  # noqa: BLE001 - policy helper retries on transport/readiness churn
            last_error = exc
        time.sleep(1.0)

    if last_error is None:
        raise TimeoutError(
            f"timed out waiting for readiness target={readiness_target} at {base_url}"
        )
    raise TimeoutError(
        f"timed out waiting for readiness target={readiness_target} at {base_url}: {last_error}"
    ) from last_error


def build_readiness_expectation(record: dict[str, object]) -> dict[str, object]:
    target = normalize_readiness_target(str(record.get("target", "")))
    epoch = record.get("epoch")
    incarnation_id = record.get("incarnation_id")

    if not isinstance(epoch, int):
        raise ValueError("readiness record must include an integer epoch")
    if not isinstance(incarnation_id, str) or not incarnation_id:
        raise ValueError("readiness record must include a non-empty incarnation_id")
    if record.get("ready") is not True:
        raise ValueError("readiness record must be ready before building an expectation")

    return {
        "expected_target": target,
        "expected_epoch": epoch,
        "expected_incarnation_id": incarnation_id,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)

    stop_play = sub.add_parser("should-stop-play")
    stop_play.add_argument("--session-status", required=True)
    stop_play.add_argument("--log-indicates-play", required=True)

    graceful_quit = sub.add_parser("should-graceful-quit")
    graceful_quit.add_argument("--session-status", required=True)

    ignore_mcp_stop = sub.add_parser("should-ignore-mcp-stop")
    ignore_mcp_stop.add_argument("--mode-label", required=True)
    ignore_mcp_stop.add_argument("--session-status", required=True)
    ignore_mcp_stop.add_argument("--log-indicates-play", required=True)

    mcp_stop_decision = sub.add_parser("mcp-stop-decision")
    mcp_stop_decision.add_argument("--mode-label", required=True)
    mcp_stop_decision.add_argument("--session-status", required=True)
    mcp_stop_decision.add_argument("--log-indicates-play", required=True)

    edit_action_success = sub.add_parser("edit-action-payload-success")
    edit_action_success.add_argument("--payload-json", required=True)

    cleanup_close = sub.add_parser("cleanup-close")
    cleanup_close.add_argument("--exit-code", type=int, required=True)
    cleanup_close.add_argument("--close-on-exit", required=True)
    cleanup_close.add_argument("--harness-owns-studio", required=True)
    cleanup_close.add_argument("--session-status", required=True)

    args = parser.parse_args()

    if args.command == "should-stop-play":
        should_stop = should_stop_play_before_quit(
            session_status=args.session_status,
            log_indicates_play=parse_bool_flag(args.log_indicates_play),
        )
        print(json.dumps({"should_stop": should_stop}, separators=(",", ":")))
        return 0

    if args.command == "cleanup-close":
        decision = decide_cleanup_close(
            exit_code=args.exit_code,
            close_on_exit=parse_bool_flag(args.close_on_exit),
            harness_owns_studio=parse_bool_flag(args.harness_owns_studio),
            session_status=args.session_status,
        )
        print(json.dumps(decision, separators=(",", ":")))
        return 0

    if args.command == "should-graceful-quit":
        print(
            json.dumps(
                {"should_quit": should_send_graceful_quit(args.session_status)},
                separators=(",", ":"),
            )
        )
        return 0

    if args.command == "should-ignore-mcp-stop":
        print(
            json.dumps(
                {
                    "should_ignore": should_ignore_mcp_stop(
                        mode_label=args.mode_label,
                        session_status=args.session_status,
                        log_indicates_play=parse_bool_flag(args.log_indicates_play),
                    )
                },
                separators=(",", ":"),
            )
        )
        return 0

    if args.command == "mcp-stop-decision":
        print(
            json.dumps(
                {
                    "decision": mcp_mode_stop_decision(
                        mode_label=args.mode_label,
                        session_status=args.session_status,
                        log_indicates_play=parse_bool_flag(args.log_indicates_play),
                    )
                },
                separators=(",", ":"),
            )
        )
        return 0

    if args.command == "edit-action-payload-success":
        try:
            payload = json.loads(args.payload_json)
        except json.JSONDecodeError:
            print(json.dumps({"success": False}, separators=(",", ":")))
            return 0
        print(
            json.dumps(
                {"success": is_successful_edit_action_payload(payload)},
                separators=(",", ":"),
            )
        )
        return 0

    return 1


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys


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

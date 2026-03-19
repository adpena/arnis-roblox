#!/usr/bin/env python3
import argparse
import json
import subprocess
import sys
import time
from enum import Enum
from pathlib import Path


class StudioState(str, Enum):
    UNKNOWN = "unknown"
    WINDOW_OPEN = "window_open"
    MENU_READY = "menu_ready"
    START_PAGE = "start_page"
    RECOVERY_BLOCKED = "recovery_blocked"
    SAVE_PROMPT = "save_prompt"
    EDITOR_READY = "editor_ready"
    PLAYING = "playing"


class StudioWorkflowController:
    def __init__(self) -> None:
        self.root = Path(__file__).resolve().parent
        self.ui_control = self.root / "studio_ui_control.py"

    def _run_control(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["python3", str(self.ui_control), *args],
            check=False,
            capture_output=True,
            text=True,
        )

    def get_state_payload(self) -> dict:
        result = self._run_control("get-state")
        if result.returncode != 0:
            return {"state": StudioState.UNKNOWN.value, "front_window": "", "window_count": 0}
        try:
            return json.loads(result.stdout.strip() or "{}")
        except json.JSONDecodeError:
            return {"state": StudioState.UNKNOWN.value, "front_window": "", "window_count": 0}

    def get_state(self) -> StudioState:
        payload = self.get_state_payload()
        raw = payload.get("state", StudioState.UNKNOWN.value)
        try:
            return StudioState(raw)
        except ValueError:
            return StudioState.UNKNOWN

    def dismiss_blockers(self) -> None:
        self._run_control("dismiss-startup-dialogs")

    def activate(self) -> None:
        self._run_control("activate")

    def trigger_new_file(self) -> None:
        self._run_control("new-file")

    def trigger_play(self) -> None:
        self._run_control("start-test-session")

    def step_toward(self, target: StudioState, state: StudioState) -> None:
        if state in (StudioState.RECOVERY_BLOCKED, StudioState.SAVE_PROMPT):
            self.dismiss_blockers()
            return

        if target == StudioState.EDITOR_READY:
            if state == StudioState.START_PAGE:
                self.trigger_new_file()
            else:
                self.activate()
            return

        if target == StudioState.PLAYING:
            if state == StudioState.START_PAGE:
                self.trigger_new_file()
                return
            if state == StudioState.EDITOR_READY:
                self.trigger_play()
                return
            self.activate()

    def is_satisfied(self, target: StudioState, state: StudioState) -> bool:
        if state == target:
            return True
        if target == StudioState.EDITOR_READY and state == StudioState.PLAYING:
            return True
        return False

    def wait_for_state(
        self,
        target: StudioState,
        timeout_seconds: int,
        retry_new_file: bool = False,
    ) -> bool:
        deadline = time.monotonic() + timeout_seconds
        retried_new = False
        last_action_at = 0.0
        while time.monotonic() < deadline:
            self.dismiss_blockers()
            state = self.get_state()
            if self.is_satisfied(target, state):
                return True
            now = time.monotonic()
            if retry_new_file and state == StudioState.START_PAGE and not retried_new:
                self.trigger_new_file()
                retried_new = True
                last_action_at = now
            elif now - last_action_at >= 1.0:
                self.step_toward(target, state)
                last_action_at = now
            time.sleep(1)
        return False


def main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("print-state")

    wait_state = sub.add_parser("wait-state")
    wait_state.add_argument("state", choices=[state.value for state in StudioState])
    wait_state.add_argument("--timeout", type=int, default=45)
    wait_state.add_argument("--retry-new-file", action="store_true")

    ensure_editor = sub.add_parser("ensure-editor-ready")
    ensure_editor.add_argument("--timeout", type=int, default=45)
    ensure_playing = sub.add_parser("ensure-playing")
    ensure_playing.add_argument("--timeout", type=int, default=20)

    args = parser.parse_args()
    controller = StudioWorkflowController()

    if args.command == "print-state":
        print(json.dumps(controller.get_state_payload(), separators=(",", ":")))
        return 0

    if args.command == "wait-state":
        ok = controller.wait_for_state(
            StudioState(args.state),
            args.timeout,
            retry_new_file=args.retry_new_file,
        )
        return 0 if ok else 1

    if args.command == "ensure-editor-ready":
        return 0 if controller.wait_for_state(StudioState.EDITOR_READY, args.timeout, retry_new_file=True) else 1

    if args.command == "ensure-playing":
        return 0 if controller.wait_for_state(StudioState.PLAYING, args.timeout) else 1

    return 1


if __name__ == "__main__":
    sys.exit(main())

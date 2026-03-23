#!/usr/bin/env python3
import argparse
import json
import subprocess
import sys

APP_ID = "com.Roblox.RobloxStudio"
APP_NAME = "RobloxStudio"
STARTUP_DISMISS_BUTTONS = [
    "Ignore",
    "Don't Recover",
    "Don’t Recover",
    "Discard",
    "Don't Save",
    "Don’t Save",
    "Cancel",
    "Close",
    "No",
]


def normalize_window_name(front_window: str) -> str:
    return front_window.strip().lower()


def is_blocking_file_panel(front_window: str) -> bool:
    normalized = normalize_window_name(front_window)
    if not normalized:
        return False
    return normalized in {
        "open roblox file",
        "open",
        "save",
        "save as",
        "export selection",
    }


def is_lighting_migration_window(front_window: str) -> bool:
    normalized = normalize_window_name(front_window)
    return "lighting" in normalized and "migration" in normalized


def is_save_close_window(front_window: str) -> bool:
    normalized = normalize_window_name(front_window)
    if not normalized:
        return False
    return (
        "save changes" in normalized
        or "want to save" in normalized
        or "before closing" in normalized
    )


def is_blocked_modal_window(front_window: str) -> bool:
    return (
        is_blocking_file_panel(front_window)
        or is_lighting_migration_window(front_window)
        or is_save_close_window(front_window)
    )


def infer_state_label(snapshot: dict) -> str:
    front_window = str(snapshot.get("front_window") or "")
    normalized_window_name = normalize_window_name(front_window)
    button_names = [str(name) for name in snapshot.get("button_names") or []]
    has_dont_recover = any(name in {"Don't Recover", "Don’t Recover"} for name in button_names)
    has_dont_save = any(name in {"Don't Save", "Don’t Save"} for name in button_names)
    has_test_menu = bool(snapshot.get("has_test_menu"))
    has_stop_menu_item_enabled = bool(snapshot.get("has_stop_menu_item_enabled"))
    has_file_menu = bool(snapshot.get("has_file_menu"))
    window_count = int(snapshot.get("window_count") or 0)

    if has_dont_recover or "auto-recovery" in normalized_window_name:
        return "recovery_blocked"
    if has_dont_save:
        return "save_prompt"
    if "auto recovered" in normalized_window_name or "recovered" in normalized_window_name:
        return "recovery_blocked"
    if "start page" in normalized_window_name or "home" in normalized_window_name:
        return "start_page"
    if has_stop_menu_item_enabled:
        return "playing"
    if has_test_menu:
        return "editor_ready"
    if normalized_window_name == "roblox studio" and not has_test_menu:
        return "start_page"
    if has_file_menu:
        return "menu_ready"
    if window_count > 0 or front_window:
        return "window_open"
    return "unknown"


def capture_process_count() -> int:
    result = subprocess.run(
        ["pgrep", "-x", APP_NAME],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return 0
    return sum(1 for line in result.stdout.splitlines() if line.strip())


def classify_session_status(snapshot: dict, pid_count: int) -> dict:
    process_running = pid_count > 0
    state = str(snapshot.get("state") or "unknown")
    front_window = str(snapshot.get("front_window") or "")
    window_count = int(snapshot.get("window_count") or 0)
    modal_window_blocked = is_blocked_modal_window(front_window)

    if not process_running:
        status = "not_running"
    elif modal_window_blocked:
        status = "blocked_dialog"
    elif state == "playing":
        status = "ready_play"
    elif state in {"editor_ready", "menu_ready"}:
        status = "ready_edit"
    elif state in {"save_prompt", "recovery_blocked"}:
        status = "blocked_dialog"
    elif state == "start_page":
        status = "start_page"
    else:
        status = "transitioning"

    return {
        "status": status,
        "state": state,
        "pid_count": pid_count,
        "process_running": process_running,
        "front_window": front_window,
        "window_count": window_count,
        "blocked_dialog": status == "blocked_dialog",
        "ready_edit": status == "ready_edit",
        "ready_play": status == "ready_play",
        "ready_for_menu": status in {"ready_edit", "ready_play"},
        "ready_for_harness": status in {"ready_edit", "ready_play", "start_page"},
        "start_page": status == "start_page",
        "transitioning": status == "transitioning",
        "safe_to_open": status in {"not_running", "start_page", "ready_edit", "ready_play"},
        "safe_to_quit": process_running,
    }


def run_osascript(script: str) -> int:
    result = subprocess.run(["osascript", "-e", script], check=False)
    return result.returncode


def capture_osascript(script: str) -> tuple[int, str]:
    result = subprocess.run(
        ["osascript", "-e", script],
        check=False,
        capture_output=True,
        text=True,
    )
    return result.returncode, result.stdout.strip()


def capture_state_snapshot() -> tuple[int, dict]:
    pid_count = capture_process_count()
    if pid_count <= 0:
        return 0, {
            "state": "not_running",
            "front_window": "",
            "window_count": 0,
            "menu_count": 0,
            "has_file_menu": False,
            "has_plugins_menu": False,
            "has_test_menu": False,
            "has_stop_menu_item": False,
            "has_stop_menu_item_enabled": False,
            "window_names": [],
            "button_names": [],
        }

    code, output = capture_osascript(
        f"""
tell application id "{APP_ID}"
  activate
end tell
delay 0.35
tell application "System Events"
  tell process "{APP_NAME}"
    set windowCount to count of windows
    set frontWindowName to ""
    if windowCount > 0 then
      try
        set frontWindowName to name of front window
      end try
    end if
    if frontWindowName is "" then
      try
        set focusedWindow to value of attribute "AXFocusedWindow"
        set frontWindowName to title of focusedWindow
      end try
    end if

    set windowNames to {{}}
    set buttonNames to {{}}
    repeat with w in windows
      try
        set end of windowNames to (name of w as text)
      end try
      try
        repeat with b in buttons of w
          try
            set end of buttonNames to (name of b as text)
          end try
        end repeat
      end try
      try
        repeat with s in sheets of w
          try
            repeat with b in buttons of s
              try
                set end of buttonNames to (name of b as text)
              end try
            end repeat
          end try
        end repeat
      end try
    end repeat

    set menuNames to {{}}
    try
      repeat with itemRef in every menu bar item of menu bar 1
        try
          set end of menuNames to (name of itemRef as text)
        end try
      end repeat
    end try

    set hasDontRecover to false
    set hasDontSave to false
    repeat with labelText in buttonNames
      if labelText is "Don't Recover" or labelText is "Don’t Recover" then
        set hasDontRecover to true
      end if
      if labelText is "Don't Save" or labelText is "Don’t Save" then
        set hasDontSave to true
      end if
    end repeat

    set hasFileMenu to false
    set hasPluginsMenu to false
    set hasTestMenu to false
    try
      set hasFileMenu to exists menu bar item "File" of menu bar 1
    end try
    try
      set hasPluginsMenu to exists menu bar item "Plugins" of menu bar 1
    end try
    try
      set hasTestMenu to exists menu bar item "Test" of menu bar 1
    end try

    set hasStopMenuItem to false
    set hasStopMenuItemEnabled to false
    if hasTestMenu then
      try
        set hasStopMenuItem to exists menu item "Stop" of menu 1 of menu bar item "Test" of menu bar 1
      end try
      if hasStopMenuItem then
        try
          set hasStopMenuItemEnabled to enabled of menu item "Stop" of menu 1 of menu bar item "Test" of menu bar 1
        end try
      end if
    end if

    set AppleScript's text item delimiters to ";;"
    set windowNamesText to ""
    try
      set windowNamesText to windowNames as text
    end try
    set buttonNamesText to ""
    try
      set buttonNamesText to buttonNames as text
    end try
    set AppleScript's text item delimiters to ""

    return frontWindowName & "||" & (windowCount as text) & "||" & (count of menuNames as text) & "||" & (hasFileMenu as text) & "||" & (hasPluginsMenu as text) & "||" & (hasTestMenu as text) & "||" & (hasStopMenuItem as text) & "||" & (hasStopMenuItemEnabled as text) & "||" & windowNamesText & "||" & buttonNamesText
  end tell
end tell
"""
    )
    if code != 0:
        return code, {}

    parts = output.split("||")
    payload = {
        "front_window": parts[0] if len(parts) > 0 else "",
        "window_count": int(parts[1]) if len(parts) > 1 and parts[1].isdigit() else 0,
        "menu_count": int(parts[2]) if len(parts) > 2 and parts[2].isdigit() else 0,
        "has_file_menu": parts[3].lower() == "true" if len(parts) > 3 else False,
        "has_plugins_menu": parts[4].lower() == "true" if len(parts) > 4 else False,
        "has_test_menu": parts[5].lower() == "true" if len(parts) > 5 else False,
        "has_stop_menu_item": parts[6].lower() == "true" if len(parts) > 6 else False,
        "has_stop_menu_item_enabled": parts[7].lower() == "true" if len(parts) > 7 else False,
        "window_names": [item for item in parts[8].split(";;") if item] if len(parts) > 8 else [],
        "button_names": [item for item in parts[9].split(";;") if item] if len(parts) > 9 else [],
    }
    payload["state"] = infer_state_label(payload)
    return 0, payload


def activate() -> int:
    return run_osascript(
        f"""
tell application id "{APP_ID}"
  activate
end tell
"""
    )


def click_menu(menu_bar_item: str, menu_item: str) -> int:
    return run_osascript(
        f"""
tell application id "{APP_ID}"
  activate
end tell
tell application "System Events"
  tell process "{APP_NAME}"
    click menu item "{menu_item}" of menu 1 of menu bar item "{menu_bar_item}" of menu bar 1
  end tell
end tell
"""
    )


def send_keystroke(key: str, command_down: bool = False) -> int:
    modifiers = " using command down" if command_down else ""
    return run_osascript(
        f"""
tell application id "{APP_ID}"
  activate
end tell
tell application "System Events"
  keystroke "{key}"{modifiers}
end tell
"""
    )


def quit_app() -> int:
    return run_osascript(
        f"""
tell application id "{APP_ID}"
  quit
end tell
"""
    )


def force_quit_app() -> int:
    result = subprocess.run(
        ["pkill", "-KILL", "-x", APP_NAME],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode not in {0, 1}:
        return result.returncode
    return 0


def dismiss_dont_save() -> int:
    return run_osascript(
        f"""
tell application "System Events"
  tell process "{APP_NAME}"
    if (count of windows) > 0 then
      repeat with w in windows
        try
          click button "Don't Save" of w
          return
        end try
        try
          click button "Don’t Save" of w
          return
        end try
      end repeat
    end if
  end tell
end tell
"""
    )


def dismiss_startup_dialogs() -> int:
    lighting_button_checks = "\n".join(
        f'''
        try
          click button "{label}" of w
          return
        end try
        try
          click button "{label}" of sheet 1 of w
          return
        end try
'''
        for label in [
            "Not Now",
            "Later",
            "Skip",
            "Cancel",
            "Close",
            "No",
            "Keep Existing",
        ]
    )
    button_checks = "\n".join(
        f'''
        try
          click button "{label}" of sheet 1 of w
          return
        end try
        try
          click button "{label}" of w
          return
        end try
'''
        for label in STARTUP_DISMISS_BUTTONS
    )
    return run_osascript(
        f"""
tell application "System Events"
  tell process "{APP_NAME}"
    if (count of windows) > 0 then
      repeat with w in windows
        try
          if name of w is "Auto-Recovery" then
            click button "Ignore" of w
            return
          end if
        end try
        try
          if name of w is "Open Roblox File" or name of w is "Open" or name of w is "Save" or name of w is "Save As" or name of w is "Export Selection" then
            try
              click button "Cancel" of w
              return
            end try
            keystroke "." using command down
            delay 0.1
            key code 53
            return
          end if
        end try
        try
          set normalizedWindowName to do shell script "printf %s " & quoted form of (name of w as text) & " | tr '[:upper:]' '[:lower:]'"
          if normalizedWindowName contains "lighting" and normalizedWindowName contains "migration" then
{lighting_button_checks}
            key code 53
            return
          end if
        end try
{button_checks}
      end repeat
    end if
  end tell
end tell
"""
    )


def get_state() -> int:
    code, payload = capture_state_snapshot()
    if code != 0:
        return code
    print(json.dumps(payload, separators=(",", ":")))
    return 0


def get_session_status() -> int:
    code, payload = capture_state_snapshot()
    if code != 0:
        return code
    pid_count = capture_process_count()
    print(json.dumps(classify_session_status(payload, pid_count), separators=(",", ":")))
    return 0


def get_state_value(field: str) -> int:
    code, payload = capture_state_snapshot()
    if code != 0:
        return code
    print(payload.get(field, ""))
    return 0


def get_session_status_value(field: str) -> int:
    code, payload = capture_state_snapshot()
    if code != 0:
        return code
    pid_count = capture_process_count()
    status = classify_session_status(payload, pid_count)
    print(status.get(field, ""))
    return 0


def dump_ui() -> int:
    code, payload = capture_state_snapshot()
    if code != 0:
        return code
    pid_count = capture_process_count()
    status = classify_session_status(payload, pid_count)
    debug_payload = dict(payload)
    debug_payload["session_status"] = status
    print(json.dumps(debug_payload, separators=(",", ":")))
    return 0


def new_file() -> int:
    result = click_menu("File", "New")
    if result == 0:
        return 0
    return send_keystroke("n", command_down=True)


def start_test_session() -> int:
    return click_menu("Test", "Start Test Session")


def stop_test_session() -> int:
    return click_menu("Test", "Stop")


def main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("activate")
    click = sub.add_parser("click-menu")
    click.add_argument("menu_bar_item")
    click.add_argument("menu_item")
    sub.add_parser("quit")
    sub.add_parser("force-quit")
    sub.add_parser("dismiss-dont-save")
    sub.add_parser("dismiss-startup-dialogs")
    sub.add_parser("get-state")
    sub.add_parser("get-session-status")
    sub.add_parser("dump-ui")
    state_value = sub.add_parser("get-state-value")
    state_value.add_argument("field", choices=["state", "front_window", "window_count"])
    session_value = sub.add_parser("get-session-status-value")
    session_value.add_argument(
        "field",
        choices=[
            "status",
            "state",
            "pid_count",
            "process_running",
            "front_window",
            "window_count",
            "blocked_dialog",
            "ready_edit",
            "ready_play",
            "ready_for_menu",
            "ready_for_harness",
            "start_page",
            "transitioning",
            "safe_to_open",
            "safe_to_quit",
        ],
    )
    sub.add_parser("new-file")
    sub.add_parser("start-test-session")
    sub.add_parser("stop-test-session")

    args = parser.parse_args()
    if args.command == "activate":
        return activate()
    if args.command == "click-menu":
        return click_menu(args.menu_bar_item, args.menu_item)
    if args.command == "quit":
        return quit_app()
    if args.command == "force-quit":
        return force_quit_app()
    if args.command == "dismiss-dont-save":
        return dismiss_dont_save()
    if args.command == "dismiss-startup-dialogs":
        return dismiss_startup_dialogs()
    if args.command == "get-state":
        return get_state()
    if args.command == "get-session-status":
        return get_session_status()
    if args.command == "dump-ui":
        return dump_ui()
    if args.command == "get-state-value":
        return get_state_value(args.field)
    if args.command == "get-session-status-value":
        return get_session_status_value(args.field)
    if args.command == "new-file":
        return new_file()
    if args.command == "start-test-session":
        return start_test_session()
    if args.command == "stop-test-session":
        return stop_test_session()
    return 1


if __name__ == "__main__":
    sys.exit(main())

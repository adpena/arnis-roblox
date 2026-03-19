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

    set buttonNames to {{}}
    repeat with w in windows
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
    if hasTestMenu then
      try
        set hasStopMenuItem to exists menu item "Stop" of menu 1 of menu bar item "Test" of menu bar 1
      end try
    end if

    set normalizedWindowName to ""
    if frontWindowName is not "" then
      set normalizedWindowName to do shell script "printf %s " & quoted form of frontWindowName & " | tr '[:upper:]' '[:lower:]'"
    end if

    set stateLabel to "unknown"
    if hasDontRecover or normalizedWindowName contains "auto-recovery" then
      set stateLabel to "recovery_blocked"
    else if hasDontSave then
      set stateLabel to "save_prompt"
    else if normalizedWindowName contains "auto recovered" or normalizedWindowName contains "recovered" then
      set stateLabel to "recovery_blocked"
    else if normalizedWindowName contains "start page" or normalizedWindowName contains "home" then
      set stateLabel to "start_page"
    else if hasStopMenuItem then
      set stateLabel to "playing"
    else if hasTestMenu then
      set stateLabel to "editor_ready"
    else if normalizedWindowName is "roblox studio" and not hasTestMenu then
      set stateLabel to "start_page"
    else if hasFileMenu then
      set stateLabel to "menu_ready"
    else if windowCount > 0 or frontWindowName is not "" then
      set stateLabel to "window_open"
    end if

    return stateLabel & "||" & frontWindowName & "||" & (windowCount as text) & "||" & (count of menuNames as text) & "||" & (hasFileMenu as text) & "||" & (hasPluginsMenu as text) & "||" & (hasTestMenu as text) & "||" & (hasStopMenuItem as text)
  end tell
end tell
"""
    )
    if code != 0:
        return code, {}

    parts = output.split("||")
    payload = {
        "state": parts[0] if len(parts) > 0 else "unknown",
        "front_window": parts[1] if len(parts) > 1 else "",
        "window_count": int(parts[2]) if len(parts) > 2 and parts[2].isdigit() else 0,
        "menu_count": int(parts[3]) if len(parts) > 3 and parts[3].isdigit() else 0,
        "has_file_menu": parts[4].lower() == "true" if len(parts) > 4 else False,
        "has_plugins_menu": parts[5].lower() == "true" if len(parts) > 5 else False,
        "has_test_menu": parts[6].lower() == "true" if len(parts) > 6 else False,
        "has_stop_menu_item": parts[7].lower() == "true" if len(parts) > 7 else False,
    }
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


def get_state_value(field: str) -> int:
    code, payload = capture_state_snapshot()
    if code != 0:
        return code
    print(payload.get(field, ""))
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
    sub.add_parser("dismiss-dont-save")
    sub.add_parser("dismiss-startup-dialogs")
    sub.add_parser("get-state")
    state_value = sub.add_parser("get-state-value")
    state_value.add_argument("field", choices=["state", "front_window", "window_count"])
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
    if args.command == "dismiss-dont-save":
        return dismiss_dont_save()
    if args.command == "dismiss-startup-dialogs":
        return dismiss_startup_dialogs()
    if args.command == "get-state":
        return get_state()
    if args.command == "get-state-value":
        return get_state_value(args.field)
    if args.command == "new-file":
        return new_file()
    if args.command == "start-test-session":
        return start_test_session()
    if args.command == "stop-test-session":
        return stop_test_session()
    return 1


if __name__ == "__main__":
    sys.exit(main())

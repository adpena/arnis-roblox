#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="RobloxStudio"
APP_BUNDLE_ID="com.Roblox.RobloxStudio"
APP_PATH="/Applications/RobloxStudio.app"
APP_EXECUTABLE="$APP_PATH/Contents/MacOS/RobloxStudio"
STUDIO_UI_CONTROL="$ROOT_DIR/scripts/studio_ui_control.py"
STUDIO_WORKFLOW="$ROOT_DIR/scripts/studio_workflow.py"
LOG_DIR="$HOME/Library/Logs/Roblox"
RUNALL_ENTRY="$ROOT_DIR/roblox/src/ServerScriptService/Tests/RunAllEntry.server.lua"
PLACE_PATH=""
PLACE_PATH_CUSTOM=0
EDIT_WAIT_SECONDS=20
PLAY_WAIT_SECONDS=25
PATTERN_WAIT_SECONDS=90
SCREENSHOT_PATH="/tmp/arnis-studio-harness.png"
DO_RESTART=0
DO_PLAY=1
KEEP_RUNALL_ENABLED=0
RUNALL_PLAY_ENABLED=0
CLOSE_ON_EXIT=1
ALLOW_TAKEOVER=0
RELAUNCH_FOR_PLAY=0
HARD_RESTART=0
MCP_BINARY="${RBX_STUDIO_MCP_BIN:-}"

if [[ -z "$MCP_BINARY" ]]; then
  MCP_BINARY="$(command -v rbx-studio-mcp || true)"
fi

if [[ -n "$MCP_BINARY" && "$MCP_BINARY" == *"roblox-studio-mcp-authority.sh" ]]; then
  LOCAL_MCP_BINARY="${HOME}/.cargo/bin/rbx-studio-mcp"
  if [[ -x "$LOCAL_MCP_BINARY" ]]; then
    MCP_BINARY="$LOCAL_MCP_BINARY"
  fi
fi

TAIL_PID=""
ACTIVE_LOG=""
RUNALL_BACKUP=""
PREVIOUS_LOG_SIZE=0
LOG_SLICE_FILE=""
PREVIOUS_LOG=""
STARTED_AT=0
CLEANUP_RUNNING=0
HARNESS_OWNS_STUDIO=0
ATTACHED_TO_EXISTING_STUDIO=0

usage() {
  cat <<'EOF'
Usage: scripts/run_studio_harness.sh [options]

Options:
  --place PATH         Open this Roblox place file instead of starting from Studio's New template.
  --edit-wait SEC      Seconds to wait for edit-mode harness completion. Default: 20
  --play-wait SEC      Seconds to wait after entering Play mode. Default: 25
  --pattern-wait SEC   Max seconds to wait for log patterns. Default: 90
  --screenshot PATH    Capture a Studio screenshot after edit/play phases. Default: /tmp/arnis-studio-harness.png
  --no-restart         Do not launch a new Studio session if one is already running.
  --no-play            Do not enter Play mode after edit-mode harness completes.
  --keep-enabled       Leave RunAllEntry.server.lua enabled after the script exits.
  --play-tests         Also enable RunAllEntry.server.lua during Play mode.
  --keep-open          Leave Roblox Studio open when the harness exits.
  --takeover           Allow the harness to attach to an already-running Studio session without restarting it.
  --hard-restart       Force a full Studio quit/relaunch cycle. Only use when takeover is insufficient.
  --relaunch-play      Relaunch Studio before Play mode. Disabled by default to avoid save-dialog churn on fresh templates.
  --help               Show this message.

This script:
  1. Temporarily enables ServerScriptService.Tests.RunAllEntry.server.lua for edit mode
  2. Restarts/open Roblox Studio
  3. Starts from File > New unless --place is supplied
  4. Streams the latest Studio log to stdout
  5. Waits for the edit-mode Roblox harness to finish
  6. Optionally enters Play mode and streams runtime Austin output
  7. Restores RunAllEntry.server.lua on exit unless --keep-enabled is set

Play mode never inherits the test suite unless --play-tests is supplied.

Accessibility permission may be required for System Events menu automation.
EOF
}

build_clean_place() {
  local roblox_dir="$ROOT_DIR/roblox"
  local build_project="$roblox_dir/default.build.project.json"
  local output_place="$roblox_dir/out/arnis-test-clean.rbxlx"

  if ! command -v rojo >/dev/null 2>&1; then
    return 0
  fi

  mkdir -p "$roblox_dir/out"

  ROOT_DIR_PY="$ROOT_DIR" python3 - <<'PY'
import json
import os
from pathlib import Path

root_dir = Path(os.environ["ROOT_DIR_PY"])
src = root_dir / "roblox" / "default.project.json"
out = root_dir / "roblox" / "default.build.project.json"
data = json.loads(src.read_text(encoding="utf-8"))
data.pop("vertigoSync", None)
data.pop("globIgnorePaths", None)
out.write_text(json.dumps(data, indent=2), encoding="utf-8")
PY

  (
    cd "$roblox_dir"
    rojo build default.build.project.json -o out/arnis-test-clean.rbxlx >/dev/null
  )
  rm -f "$build_project"

  [[ -f "$output_place" ]]
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --place)
      PLACE_PATH="$2"
      PLACE_PATH_CUSTOM=1
      shift 2
      ;;
    --edit-wait)
      EDIT_WAIT_SECONDS="$2"
      shift 2
      ;;
    --play-wait)
      PLAY_WAIT_SECONDS="$2"
      shift 2
      ;;
    --pattern-wait)
      PATTERN_WAIT_SECONDS="$2"
      shift 2
      ;;
    --screenshot)
      SCREENSHOT_PATH="$2"
      shift 2
      ;;
    --no-restart)
      DO_RESTART=0
      shift
      ;;
    --no-play)
      DO_PLAY=0
      shift
      ;;
    --keep-enabled)
      KEEP_RUNALL_ENABLED=1
      shift
      ;;
    --play-tests)
      RUNALL_PLAY_ENABLED=1
      shift
      ;;
    --keep-open)
      CLOSE_ON_EXIT=0
      shift
      ;;
    --takeover)
      ALLOW_TAKEOVER=1
      shift
      ;;
    --hard-restart)
      HARD_RESTART=1
      DO_RESTART=1
      shift
      ;;
    --relaunch-play)
      RELAUNCH_FOR_PLAY=1
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "[harness] unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ $PLACE_PATH_CUSTOM -eq 1 && ! -f "$PLACE_PATH" ]]; then
  echo "[harness] place file not found: $PLACE_PATH" >&2
  exit 1
fi

if [[ ! -f "$RUNALL_ENTRY" ]]; then
  echo "[harness] RunAllEntry not found: $RUNALL_ENTRY" >&2
  exit 1
fi

log() {
  printf '[harness] %s\n' "$*"
}

latest_studio_log() {
  ls -t "$LOG_DIR"/*_Studio_*_last.log 2>/dev/null | head -n 1 || true
}

studio_pids() {
  pgrep -x "RobloxStudio" 2>/dev/null || true
}

restore_runall_entry() {
  if [[ -n "$RUNALL_BACKUP" && -f "$RUNALL_BACKUP" && $KEEP_RUNALL_ENABLED -eq 0 ]]; then
    cp "$RUNALL_BACKUP" "$RUNALL_ENTRY"
  fi
  if [[ -n "$RUNALL_BACKUP" && -f "$RUNALL_BACKUP" ]]; then
    rm -f "$RUNALL_BACKUP"
  fi
}

set_runall_entry_modes() {
  local edit_enabled="$1"
  local play_enabled="$2"
  python3 - "$RUNALL_ENTRY" "$edit_enabled" "$play_enabled" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
edit_enabled = sys.argv[2].lower() == "true"
play_enabled = sys.argv[3].lower() == "true"
text = path.read_text(encoding="utf-8")
edit_markers = ("local RUN_IN_EDIT_MODE = true", "local RUN_IN_EDIT_MODE = false")
play_markers = ("local RUN_IN_PLAY_MODE = true", "local RUN_IN_PLAY_MODE = false")

for old in edit_markers:
    if old in text:
        text = text.replace(old, f"local RUN_IN_EDIT_MODE = {'true' if edit_enabled else 'false'}", 1)
        break
else:
    raise SystemExit("RunAllEntry edit-mode toggle constant not found")

for old in play_markers:
    if old in text:
        text = text.replace(old, f"local RUN_IN_PLAY_MODE = {'true' if play_enabled else 'false'}", 1)
        break
else:
    raise SystemExit("RunAllEntry play-mode toggle constant not found")

path.write_text(text, encoding="utf-8")
PY
}

disable_runall_entry() {
  set_runall_entry_modes false false
}

cleanup() {
  if [[ $CLEANUP_RUNNING -eq 1 ]]; then
    return
  fi
  CLEANUP_RUNNING=1
  stop_log_pipe
  if [[ -n "$LOG_SLICE_FILE" && -f "$LOG_SLICE_FILE" ]]; then
    rm -f "$LOG_SLICE_FILE"
  fi
  if [[ $CLOSE_ON_EXIT -eq 1 && $HARNESS_OWNS_STUDIO -eq 1 ]]; then
    quit_studio
  fi
  restore_runall_entry
}

trap cleanup EXIT
trap 'exit 130' INT TERM

enable_runall_entry() {
  local play_enabled="false"
  if [[ $RUNALL_PLAY_ENABLED -eq 1 ]]; then
    play_enabled="true"
  fi
  RUNALL_BACKUP="$(mktemp)"
  cp "$RUNALL_ENTRY" "$RUNALL_BACKUP"
  set_runall_entry_modes true "$play_enabled"
}

quit_studio() {
  stop_play_mode || true

  python3 "$STUDIO_UI_CONTROL" quit >/dev/null 2>&1 || true

  local waited=0
  while [[ -n "$(studio_pids)" ]]; do
    sleep 1
    waited=$((waited + 1))
    if [[ $waited -ge 3 ]]; then
      python3 "$STUDIO_UI_CONTROL" dismiss-dont-save >/dev/null 2>&1 || true
    fi
    if [[ $waited -ge 20 ]]; then
      local pid
      for pid in $(studio_pids); do
        kill -TERM "$pid" >/dev/null 2>&1 || true
      done
    fi
    if [[ $waited -ge 28 ]]; then
      local pid
      for pid in $(studio_pids); do
        kill -KILL "$pid" >/dev/null 2>&1 || true
      done
      break
    fi
  done
}

open_studio() {
  HARNESS_OWNS_STUDIO=1
  local attempts=0
  while [[ $attempts -lt 5 ]]; do
    if [[ $PLACE_PATH_CUSTOM -eq 1 ]]; then
      if [[ -d "$APP_PATH" ]]; then
        if open -a "$APP_PATH" "$PLACE_PATH"; then
          return 0
        fi
      elif open -b "$APP_BUNDLE_ID" "$PLACE_PATH"; then
        return 0
      fi
    else
      if [[ -d "$APP_PATH" ]]; then
        if open -a "$APP_PATH"; then
          return 0
        fi
      elif open -b "$APP_BUNDLE_ID"; then
        return 0
      fi
    fi

    attempts=$((attempts + 1))
    sleep 2
  done

  return 1
}

wait_for_new_log() {
  local previous_log="$1"
  local started_at="$2"
  local waited=0
  while [[ $waited -lt $PATTERN_WAIT_SECONDS ]]; do
    dismiss_startup_dialogs
    local newest
    newest="$(latest_studio_log)"
    if [[ -n "$newest" ]]; then
      if [[ "$newest" != "$previous_log" ]]; then
        printf '%s\n' "$newest"
        return 0
      fi
      local mtime
      mtime="$(stat -f '%m' "$newest" 2>/dev/null || echo 0)"
      if [[ "$mtime" -ge "$started_at" ]]; then
        printf '%s\n' "$newest"
        return 0
      fi
    fi
    sleep 1
    waited=$((waited + 1))
  done
  return 1
}

wait_for_different_log() {
  local previous_log="$1"
  local waited=0
  while [[ $waited -lt $PATTERN_WAIT_SECONDS ]]; do
    dismiss_startup_dialogs
    local newest
    newest="$(latest_studio_log)"
    if [[ -n "$newest" && "$newest" != "$previous_log" ]]; then
      printf '%s\n' "$newest"
      return 0
    fi
    sleep 1
    waited=$((waited + 1))
  done
  return 1
}

start_log_pipe() {
  local log_file="$1"
  local start_byte=1
  if [[ "$log_file" == "$PREVIOUS_LOG" && $PREVIOUS_LOG_SIZE -gt 0 ]]; then
    start_byte=$((PREVIOUS_LOG_SIZE + 1))
  fi
  python3 - "$log_file" "$start_byte" "${LOG_SLICE_FILE:-}" <<'PY' &
import os
import re
import signal
import sys
import time

log_file = sys.argv[1]
start_byte = max(1, int(sys.argv[2]))
slice_file = sys.argv[3] if len(sys.argv) > 3 else ""
running = True
suppressed_count = 0

NOISY_PATTERNS = [
    re.compile(r"localhost port 44755", re.IGNORECASE),
    re.compile(r"http://localhost:44755/request", re.IGNORECASE),
    re.compile(r"HttpError: ConnectFail", re.IGNORECASE),
]

def stop(_signum, _frame):
    global running
    running = False

signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGINT, stop)
signal.signal(signal.SIGPIPE, signal.SIG_DFL)

def emit(line: str) -> None:
    global running
    try:
        sys.stdout.write(f"[studio] {line}\n")
        sys.stdout.flush()
    except BrokenPipeError:
        running = False
        return
    if slice_file:
        try:
            with open(slice_file, "a", encoding="utf-8") as fh:
                fh.write(line)
                fh.write("\n")
        except OSError:
            running = False

def should_suppress(line: str) -> bool:
    return any(pattern.search(line) for pattern in NOISY_PATTERNS)

position = start_byte - 1
inode = None
handle = None

while running:
    try:
        stat = os.stat(log_file)
    except FileNotFoundError:
        time.sleep(0.25)
        continue

    if handle is None or inode != stat.st_ino:
        if handle is not None:
            handle.close()
        handle = open(log_file, "r", encoding="utf-8", errors="replace")
        inode = stat.st_ino
        position = min(position, stat.st_size)
        handle.seek(position)
    elif stat.st_size < position:
        handle.close()
        handle = open(log_file, "r", encoding="utf-8", errors="replace")
        position = 0
        handle.seek(position)

    line = handle.readline()
    if line:
        position = handle.tell()
        text = line.rstrip("\n")
        if should_suppress(text):
            suppressed_count += 1
            continue
        emit(text)
        continue

    time.sleep(0.2)

if suppressed_count:
    emit(f"[harness] suppressed {suppressed_count} repeated localhost:44755 relay errors")

if handle is not None:
    handle.close()
PY
  TAIL_PID=$!
}

stop_log_pipe() {
  if [[ -z "$TAIL_PID" ]]; then
    return
  fi
  kill "$TAIL_PID" >/dev/null 2>&1 || true
  wait "$TAIL_PID" >/dev/null 2>&1 || true
  TAIL_PID=""
}

prepare_log_cursor() {
  PREVIOUS_LOG="$(latest_studio_log)"
  PREVIOUS_LOG_SIZE=0
  if [[ -n "$PREVIOUS_LOG" && -f "$PREVIOUS_LOG" ]]; then
    PREVIOUS_LOG_SIZE="$(stat -f '%z' "$PREVIOUS_LOG" 2>/dev/null || echo 0)"
  fi
  STARTED_AT="$(date +%s)"
  if [[ -n "$LOG_SLICE_FILE" && -f "$LOG_SLICE_FILE" ]]; then
    rm -f "$LOG_SLICE_FILE"
  fi
  LOG_SLICE_FILE="$(mktemp)"
}

wait_for_studio_process() {
  local waited=0
  while [[ $waited -lt $PATTERN_WAIT_SECONDS ]]; do
    dismiss_startup_dialogs
    if [[ -n "$(studio_pids)" ]]; then
      return 0
    fi
    sleep 1
    waited=$((waited + 1))
  done
  return 1
}

wait_for_mcp_ready() {
  if [[ -z "$MCP_BINARY" || ! -x "$MCP_BINARY" ]]; then
    return 0
  fi

  local waited=0
  while [[ $waited -lt $PATTERN_WAIT_SECONDS ]]; do
    dismiss_startup_dialogs
    if MCP_BINARY_PATH="$MCP_BINARY" python3 - <<'PY' >/dev/null 2>&1
import os
import sys
sys.path.insert(0, '/Users/adpena/Projects/vertigo/scripts/dev')
from studio_mcp_direct_lib import JsonRpcStdioClient

client = JsonRpcStdioClient(
    os.environ["MCP_BINARY_PATH"],
    timeout_seconds=8,
    protocol_version='2025-11-25',
    client_name='arnis-studio-harness-ready',
)
try:
    client.initialize()
    client.call_tool("get_studio_mode", {})
finally:
    client.close()
PY
    then
      return 0
    fi
    sleep 2
    waited=$((waited + 2))
  done
  return 1
}

relaunch_studio_for_phase() {
  local phase_label="$1"
  if [[ $ATTACHED_TO_EXISTING_STUDIO -eq 1 ]]; then
    log "refusing to relaunch Studio during $phase_label phase while attached to an existing session"
    return 1
  fi
  stop_log_pipe

  prepare_log_cursor
  log "relaunching Studio for $phase_label phase"
  quit_studio
  open_studio || {
    echo "[harness] failed to relaunch Roblox Studio for $phase_label phase" >&2
    exit 1
  }
  wait_for_studio_process || {
    echo "[harness] Studio process failed to appear during $phase_label relaunch" >&2
    exit 1
  }

  ACTIVE_LOG="$(wait_for_new_log "$PREVIOUS_LOG" "$STARTED_AT")" || {
    echo "[harness] failed to detect a new Studio log file during $phase_label relaunch" >&2
    exit 1
  }

  switch_to_log "$ACTIVE_LOG"
  if [[ $PLACE_PATH_CUSTOM -eq 0 ]]; then
    follow_new_template_handoff
  fi
  wait_for_editor_ready "$PATTERN_WAIT_SECONDS" || {
    log "Studio editor did not become ready during $phase_label relaunch; continuing with best effort"
  }
  wait_for_mcp_ready || {
    log "Studio MCP helper did not become ready during $phase_label relaunch; continuing without MCP readiness gate"
  }
  if [[ "$phase_label" == "play" ]]; then
    wait_for_log_pattern "\\[VertigoSync\\] Snapshot reconciled|\\[VertigoSync\\] Plugin initialized" "$PATTERN_WAIT_SECONDS" || {
      log "play relaunch did not reach VertigoSync readiness before timeout; continuing"
    }
  fi
}

wait_for_log_pattern() {
  local pattern="$1"
  local timeout="$2"
  local waited=0
  while [[ $waited -lt $timeout ]]; do
    dismiss_startup_dialogs
    if [[ -n "$ACTIVE_LOG" ]] && grep -qE "$pattern" "$ACTIVE_LOG"; then
      return 0
    fi
    sleep 1
    waited=$((waited + 1))
  done
  return 1
}

wait_for_edit_completion() {
  if wait_for_log_pattern "TestEZ tests complete|Tests failed|\\[AustinPreviewBuilder\\] sync complete" "$PATTERN_WAIT_SECONDS"; then
    return 0
  fi
  return 1
}

activate_studio() {
  python3 "$STUDIO_UI_CONTROL" activate >/dev/null 2>&1 || true
}

dismiss_startup_dialogs() {
  python3 "$STUDIO_UI_CONTROL" dismiss-startup-dialogs >/dev/null 2>&1 || true
}

studio_state_json() {
  python3 "$STUDIO_UI_CONTROL" get-state 2>/dev/null || true
}

wait_for_editor_ready() {
  local timeout="${1:-45}"
  python3 "$STUDIO_WORKFLOW" ensure-editor-ready --timeout "$timeout" >/dev/null 2>&1
}

wait_for_playing() {
  local timeout="${1:-20}"
  python3 "$STUDIO_WORKFLOW" ensure-playing --timeout "$timeout" >/dev/null 2>&1
}

switch_to_log() {
  local log_file="$1"
  stop_log_pipe
  ACTIVE_LOG="$log_file"
  log "streaming Studio log: $ACTIVE_LOG"
  start_log_pipe "$ACTIVE_LOG"
  activate_studio
}

follow_new_template_handoff() {
  prepare_log_cursor
  log "creating a fresh new experience"
  activate_studio
  sleep 1
  dismiss_startup_dialogs
  if ! new_file_template; then
    log "failed to trigger File > New; continuing with current Studio session"
    return 0
  fi

  local next_log=""
  next_log="$(wait_for_different_log "$ACTIVE_LOG")" || true
  if [[ -n "$next_log" && "$next_log" != "$ACTIVE_LOG" ]]; then
    log "detected Studio handoff to a fresh template instance"
    switch_to_log "$next_log"
    wait_for_editor_ready "$PATTERN_WAIT_SECONDS" || {
      log "fresh template did not reach editor-ready state before timeout; continuing with best effort"
    }
    wait_for_mcp_ready || {
      log "Studio MCP helper did not become ready after File > New; continuing without MCP readiness gate"
    }
  else
    wait_for_editor_ready 10 || sleep 3
  fi
  dismiss_startup_dialogs
}

capture_studio_screenshot() {
  local phase="$1"
  if [[ -z "$SCREENSHOT_PATH" ]]; then
    return 0
  fi

  local target="$SCREENSHOT_PATH"
  if [[ "$target" == *".png" ]]; then
    target="${target%.png}-${phase}.png"
  else
    target="${target}-${phase}.png"
  fi

  activate_studio
  sleep 1
  screencapture -x "$target"
  log "captured Studio screenshot: $target"
}

capture_mcp_probe() {
  local phase="$1"
  if [[ -z "$MCP_BINARY" || ! -x "$MCP_BINARY" ]]; then
    return 0
  fi

  MCP_PHASE="$phase" MCP_BINARY_PATH="$MCP_BINARY" python3 - <<'PY'
import json
import os
import signal
import sys

sys.path.insert(0, '/Users/adpena/Projects/vertigo/scripts/dev')
from studio_mcp_direct_lib import JsonRpcStdioClient

phase = os.environ["MCP_PHASE"]
bin_path = os.environ["MCP_BINARY_PATH"]
timeout_seconds = 8

def on_alarm(_signum, _frame):
    raise TimeoutError(f"capture_mcp_probe timed out after {timeout_seconds}s")

signal.signal(signal.SIGALRM, on_alarm)
signal.alarm(timeout_seconds)

client = None

try:
    client = JsonRpcStdioClient(
        bin_path,
        timeout_seconds=6,
        protocol_version='2025-11-25',
        client_name='arnis-studio-harness',
    )
    client.initialize()
    mode_result = client.call_tool("get_studio_mode", {})
    print(f"[harness-mcp] phase={phase} mode={json.dumps(mode_result, separators=(',', ':'))}")

    if phase == "edit":
        result = client.call_tool(
            "run_code",
            {
                "command": """
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")
local root = Workspace:FindFirstChild("GeneratedWorld_AustinPreview")
local focus = root and root:FindFirstChild("PreviewFocus")
local pad = focus and focus:FindFirstChild("Pad")
local plane = focus and focus:FindFirstChild("GroundPlane")
local chunkCount = 0
if root then
    for _, child in ipairs(root:GetChildren()) do
        if child:IsA("Folder") and child.Name ~= "PreviewFocus" then
            chunkCount += 1
        end
    end
end
local payload = {
    rootExists = root ~= nil,
    chunkCount = chunkCount,
    padY = pad and pad.Position.Y or nil,
    planeY = plane and plane.Position.Y or nil,
    timeTravelState = Workspace:GetAttribute("VertigoSyncTimeTravelState"),
    previewState = Workspace:GetAttribute("VertigoPreviewSyncState"),
    previewPhase = Workspace:GetAttribute("VertigoPreviewSyncPhase"),
    austinFocusX = Workspace:GetAttribute("VertigoAustinFocusX"),
    austinFocusZ = Workspace:GetAttribute("VertigoAustinFocusZ"),
    austinSpawnX = Workspace:GetAttribute("VertigoAustinSpawnX"),
    austinSpawnY = Workspace:GetAttribute("VertigoAustinSpawnY"),
    austinSpawnZ = Workspace:GetAttribute("VertigoAustinSpawnZ"),
}
print("ARNIS_MCP_EDIT " .. HttpService:JSONEncode(payload))
""".strip()
            },
            allow_is_error=True,
        )
        print(f"[harness-mcp] phase=edit run_code={json.dumps(result, separators=(',', ':'))}")
    else:
        console = client.call_tool("get_console_output", {}, allow_is_error=True)
        print(f"[harness-mcp] phase={phase} console={json.dumps(console, separators=(',', ':'))}")
except Exception as exc:
    print(f"[harness-mcp] phase={phase} error={exc!r}")
finally:
    signal.alarm(0)
    if client is not None:
        client.close()
PY
}

run_probe_best_effort() {
  local phase="$1"
  local timeout="$2"

  if [[ -z "$MCP_BINARY" || ! -x "$MCP_BINARY" ]]; then
    return 0
  fi

  (
    capture_mcp_probe "$phase"
  ) &
  local probe_pid=$!
  local waited=0

  while kill -0 "$probe_pid" >/dev/null 2>&1; do
    if [[ $waited -ge $timeout ]]; then
      log "MCP probe for $phase exceeded ${timeout}s; continuing without waiting"
      kill -TERM "$probe_pid" >/dev/null 2>&1 || true
      wait "$probe_pid" >/dev/null 2>&1 || true
      return 0
    fi
    sleep 1
    waited=$((waited + 1))
  done

  wait "$probe_pid" >/dev/null 2>&1 || true
}

click_menu_item() {
  local menu_bar_item="$1"
  local menu_item="$2"
  local attempts=0
  while [[ $attempts -lt 15 ]]; do
    if python3 "$STUDIO_UI_CONTROL" click-menu "$menu_bar_item" "$menu_item" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
    attempts=$((attempts + 1))
  done
  return 1
}

new_file_template() {
  python3 "$STUDIO_UI_CONTROL" new-file >/dev/null 2>&1 || click_menu_item "File" "New"
}

enter_play_mode() {
  if python3 "$STUDIO_UI_CONTROL" start-test-session >/dev/null 2>&1; then
    return 0
  fi
  if click_menu_item "Test" "Start Test Session"; then
    return 0
  fi
  if click_menu_item "Test" "Play"; then
    return 0
  fi
  python3 "$STUDIO_UI_CONTROL" activate >/dev/null 2>&1 || true
  osascript -e 'tell application "System Events" to key code 96' >/dev/null 2>&1 || true
}

stop_play_mode() {
  if [[ -n "$MCP_BINARY" && -x "$MCP_BINARY" ]]; then
    MCP_BINARY_PATH="$MCP_BINARY" python3 - <<'PY' >/dev/null 2>&1 || true
import os
import sys
sys.path.insert(0, '/Users/adpena/Projects/vertigo/scripts/dev')
from studio_mcp_direct_lib import JsonRpcStdioClient

client = JsonRpcStdioClient(
    os.environ["MCP_BINARY_PATH"],
    timeout_seconds=12,
    protocol_version='2025-11-25',
    client_name='arnis-studio-harness-stop-play',
)
try:
    client.initialize()
    client.call_tool("start_stop_play", {"mode": "stop"}, allow_is_error=True)
finally:
    client.close()
PY
    return 0
  fi
  if python3 "$STUDIO_UI_CONTROL" stop-test-session >/dev/null 2>&1; then
    return 0
  fi
  if click_menu_item "Test" "Stop"; then
    return 0
  fi
}

run_play_probe_via_mcp() {
  if [[ -z "$MCP_BINARY" || ! -x "$MCP_BINARY" ]]; then
    return 1
  fi

  MCP_BINARY_PATH="$MCP_BINARY" MCP_PLAY_WAIT="$PLAY_WAIT_SECONDS" python3 - <<'PY'
import json
import os
import signal
import sys

sys.path.insert(0, '/Users/adpena/Projects/vertigo/scripts/dev')
from studio_mcp_direct_lib import JsonRpcStdioClient

wait_seconds = max(5, int(os.environ.get("MCP_PLAY_WAIT", "25")))
wall_clock_timeout = max(wait_seconds + 45, 90)

def on_alarm(_signum, _frame):
    raise TimeoutError(f"run_play_probe_via_mcp timed out after {wall_clock_timeout}s")

signal.signal(signal.SIGALRM, on_alarm)
signal.alarm(wall_clock_timeout)

client = JsonRpcStdioClient(
    os.environ["MCP_BINARY_PATH"],
    timeout_seconds=max(wait_seconds + 30, 60),
    protocol_version='2025-11-25',
    client_name='arnis-studio-harness-play',
)

luau = f"""
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local function vectorToTable(v)
    if typeof(v) ~= "Vector3" then
        return nil
    end
    return {{
        x = math.round(v.X * 100) / 100,
        y = math.round(v.Y * 100) / 100,
        z = math.round(v.Z * 100) / 100,
    }}
end

local function sample()
    local player = Players:GetPlayers()[1]
    local character = player and player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local generated = Workspace:FindFirstChild("GeneratedWorld_Austin")
    local spawn = Workspace:FindFirstChild("CongressAveSpawn")
    local loadingPad = Workspace:FindFirstChild("AustinLoadingPad")
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    raycastParams.FilterDescendantsInstances = {{}}
    if character then
        table.insert(raycastParams.FilterDescendantsInstances, character)
    end
    local payload = {{
        player = player and player.Name or nil,
        root = root and vectorToTable(root.Position) or nil,
        generatedExists = generated ~= nil,
        generatedChildren = generated and #generated:GetChildren() or 0,
        spawn = spawn and vectorToTable(spawn.Position) or nil,
        loadingPad = loadingPad and vectorToTable(loadingPad.Position) or nil,
    }}
    if root then
        local hit = Workspace:Raycast(root.Position + Vector3.new(0, 4, 0), Vector3.new(0, -2000, 0), raycastParams)
        payload.ground = hit and {{
            position = vectorToTable(hit.Position),
            distance = math.round((root.Position.Y - hit.Position.Y) * 100) / 100,
            instance = hit.Instance and hit.Instance:GetFullName() or nil,
            material = tostring(hit.Material),
        }} or nil
    end
    payload.timeTravelState = Workspace:GetAttribute("VertigoSyncTimeTravelState")
    payload.previewState = Workspace:GetAttribute("VertigoPreviewSyncState")
    payload.previewPhase = Workspace:GetAttribute("VertigoPreviewSyncPhase")
    payload.austinFocusX = Workspace:GetAttribute("VertigoAustinFocusX")
    payload.austinFocusZ = Workspace:GetAttribute("VertigoAustinFocusZ")
    payload.austinSpawnX = Workspace:GetAttribute("VertigoAustinSpawnX")
    payload.austinSpawnY = Workspace:GetAttribute("VertigoAustinSpawnY")
    payload.austinSpawnZ = Workspace:GetAttribute("VertigoAustinSpawnZ")
    return payload
end

task.wait({wait_seconds})
print("ARNIS_MCP_PLAY " .. HttpService:JSONEncode(sample()))
task.wait(2)
print("ARNIS_MCP_PLAY_LATE " .. HttpService:JSONEncode(sample()))
""".strip()

try:
    client.initialize()
    result = client.call_tool(
        "run_script_in_play_mode",
        {"mode": "start_play", "code": luau, "timeout": max(wait_seconds + 30, 60)},
        allow_is_error=True,
        timeout_seconds=max(wait_seconds + 35, 70),
    )
    print(f"[harness-mcp] phase=play run_script={json.dumps(result, separators=(',', ':'))}")
finally:
    signal.alarm(0)
    try:
        client.call_tool("start_stop_play", {"mode": "stop"}, allow_is_error=True)
    except Exception:
        pass
    client.close()
PY
}

summarize_log() {
  local summary_source="$ACTIVE_LOG"
  if [[ -n "$LOG_SLICE_FILE" && -f "$LOG_SLICE_FILE" ]]; then
    summary_source="$LOG_SLICE_FILE"
  fi
  log "summary from $(basename "$ACTIVE_LOG")"
  grep -E "TestEZ tests complete|PASS |FAIL |Tests failed|BootstrapAustin|RunAustin|AustinPreviewBuilder|ArnisRoblox|VertigoSync|RunAll|Austin anchor|anchor resolved|ARNIS_MCP_PLAY|ARNIS_MCP_PLAY_LATE|ARNIS_MCP_EDIT|\\[harness-mcp\\]" "$summary_source" | tail -n 220 || true
}

if [[ $PLACE_PATH_CUSTOM -eq 1 ]]; then
  build_clean_place || true
fi
enable_runall_entry

prepare_log_cursor

CURRENT_STUDIO_PIDS="$(studio_pids)"
if [[ -n "$CURRENT_STUDIO_PIDS" ]]; then
  if [[ $ALLOW_TAKEOVER -eq 0 ]]; then
    echo "[harness] Roblox Studio is already running; refusing to take over it without --takeover" >&2
    exit 1
  fi

  if [[ $HARD_RESTART -eq 1 ]]; then
    log "hard restarting Roblox Studio"
    quit_studio
    if [[ $PLACE_PATH_CUSTOM -eq 1 ]]; then
      log "opening place: $PLACE_PATH"
    else
      log "opening Studio on a fresh New template"
    fi
    open_studio
    ACTIVE_LOG="$(wait_for_new_log "$PREVIOUS_LOG" "$STARTED_AT")" || {
      echo "[harness] failed to detect a new Studio log file" >&2
      exit 1
    }
    switch_to_log "$ACTIVE_LOG"
    if [[ $PLACE_PATH_CUSTOM -eq 0 ]]; then
      follow_new_template_handoff
    fi
  else
    log "attaching to existing Roblox Studio session"
    ATTACHED_TO_EXISTING_STUDIO=1
    CLOSE_ON_EXIT=0
    RELAUNCH_FOR_PLAY=0
    ACTIVE_LOG="$(latest_studio_log)"
    if [[ -z "$ACTIVE_LOG" ]]; then
      echo "[harness] failed to locate an existing Studio log file while attaching" >&2
      exit 1
    fi
    switch_to_log "$ACTIVE_LOG"
    wait_for_editor_ready "$PATTERN_WAIT_SECONDS" || {
      log "attached Studio session did not become editor-ready before timeout; continuing with best effort"
    }
  fi
else
  if [[ $PLACE_PATH_CUSTOM -eq 1 ]]; then
    log "opening place: $PLACE_PATH"
  else
    log "opening Studio on a fresh New template"
  fi
  open_studio
  ACTIVE_LOG="$(wait_for_new_log "$PREVIOUS_LOG" "$STARTED_AT")" || {
    echo "[harness] failed to detect a new Studio log file" >&2
    exit 1
  }
  switch_to_log "$ACTIVE_LOG"
  if [[ $PLACE_PATH_CUSTOM -eq 0 ]]; then
    follow_new_template_handoff
  fi
fi

if [[ -n "$MCP_BINARY" ]]; then
  log "detected Studio MCP helper: $MCP_BINARY"
else
  log "Studio MCP helper not found in PATH (rbx-studio-mcp); localhost plugin integration may be unavailable"
fi

CURRENT_STUDIO_STATE="$(python3 "$STUDIO_UI_CONTROL" get-state-value state 2>/dev/null || true)"
if [[ $ATTACHED_TO_EXISTING_STUDIO -eq 1 && "$CURRENT_STUDIO_STATE" == "playing" ]]; then
  log "attached Studio session is already in play; skipping edit-mode setup"
  DO_PLAY=0
fi

if [[ $ATTACHED_TO_EXISTING_STUDIO -eq 0 || "$CURRENT_STUDIO_STATE" != "playing" ]]; then
  log "waiting for edit-mode harness output"
  if wait_for_edit_completion; then
    sleep "$EDIT_WAIT_SECONDS"
  else
    log "edit-mode harness result not observed before timeout; continuing with captured output"
  fi
  log "capturing edit screenshot"
  capture_studio_screenshot "edit"
  log "capturing edit MCP probe"
  run_probe_best_effort "edit" 5
fi

if [[ $ATTACHED_TO_EXISTING_STUDIO -eq 1 && "$CURRENT_STUDIO_STATE" == "playing" ]]; then
  log "capturing attached play screenshot"
  capture_studio_screenshot "play"
  run_probe_best_effort "play" 8
elif [[ $DO_PLAY -eq 1 ]]; then
  if [[ $KEEP_RUNALL_ENABLED -eq 0 ]]; then
    log "disabling RunAll before play"
    disable_runall_entry
  fi
  if [[ $RELAUNCH_FOR_PLAY -eq 1 ]]; then
    relaunch_studio_for_phase "play" || log "play relaunch refused or failed; continuing in current session"
  fi
  log "entering Play mode"
  activate_studio
  if run_play_probe_via_mcp; then
    sleep 2
  else
    enter_play_mode || log "failed to trigger Play mode via AppleScript/menu automation"
    wait_for_playing 20 || log "Studio did not report playing state before timeout; falling back to Austin log markers"
    if wait_for_log_pattern "\\[BootstrapAustin\\] Starting Austin, TX import|\\[RunAustin\\]|\\[BootstrapAustin\\] Done\\." "$PATTERN_WAIT_SECONDS"; then
      sleep "$PLAY_WAIT_SECONDS"
    else
      log "play-mode Austin markers not observed before timeout; continuing"
    fi
  fi
  capture_studio_screenshot "play"
  run_probe_best_effort "play" 8
  stop_play_mode || true
fi

summarize_log

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="RobloxStudio"
APP_BUNDLE_ID="com.Roblox.RobloxStudio"
APP_PATH="/Applications/RobloxStudio.app"
APP_EXECUTABLE="$APP_PATH/Contents/MacOS/RobloxStudio"
STUDIO_UI_CONTROL="$ROOT_DIR/scripts/studio_ui_control.py"
STUDIO_WORKFLOW="$ROOT_DIR/scripts/studio_workflow.py"
STUDIO_HARNESS_POLICY="$ROOT_DIR/scripts/studio_harness_policy.py"
LOG_DIR="$HOME/Library/Logs/Roblox"
ROBLOX_PLUGIN_DIR="${ROBLOX_PLUGIN_DIR:-$HOME/Documents/Roblox/Plugins}"
ROBLOX_STUDIO_STATE_DIR="$HOME/Library/Application Support/Roblox/RobloxStudio"
ROBLOX_AUTOSAVE_DIR="$ROBLOX_STUDIO_STATE_DIR/AutoSaves"
RUNALL_CONFIG="$ROOT_DIR/roblox/src/ServerScriptService/Tests/RunAllConfig.lua"
VSYNC_REPO_DIR="${VSYNC_REPO_DIR:-$(cd "$ROOT_DIR/.." && pwd)/vertigo-sync}"
PLACE_PATH=""
PLACE_PATH_CUSTOM=0
AUTO_BUILT_PLACE=0
EDIT_WAIT_SECONDS=20
PLAY_WAIT_SECONDS=25
PATTERN_WAIT_SECONDS=90
MCP_READY_WAIT_SECONDS="${HARNESS_MCP_READY_WAIT_SECONDS:-12}"
SCREENSHOT_PATH="/tmp/arnis-studio-harness.png"
DO_RESTART=1
DO_PLAY=1
KEEP_RUNALL_ENABLED=0
RUNALL_EDIT_ENABLED=0
RUNALL_PLAY_ENABLED=0
RUNALL_SPEC_FILTER=""
CLOSE_ON_EXIT=1
ALLOW_TAKEOVER=0
RELAUNCH_FOR_PLAY=0
HARD_RESTART=0
SKIP_PLUGIN_SMOKE=0
SCENE_INDEX_VERSION=2
STUDIO_RELAUNCH_COOLDOWN_SECONDS=3
MCP_BINARY="${RBX_STUDIO_MCP_BIN:-}"
VSYNC_BINARY="${VSYNC_BIN:-}"
VSYNC_SOURCE_REPO=0
VSYNC_SERVER_URL=""
VSYNC_SERVER_PID=""
VSYNC_SERVER_LOG=""
MCP_READY=0
SCENE_MARKER_LUAU=""
read -r -d '' SCENE_MARKER_LUAU <<'LUA' || true
local function cloneStatsWithoutSourceIds(stats)
    local cloned = {}
    if typeof(stats) ~= "table" then
        return cloned
    end
    for statsKey, statsValue in pairs(stats) do
        if statsKey ~= "sourceIds" and statsKey ~= "_sourceIdSet" then
            cloned[statsKey] = statsValue
        end
    end
    return cloned
end

local function emitSourceIdBatches(marker, suffix, phase, rootName, bucket, sourceIds)
    if typeof(sourceIds) ~= "table" or #sourceIds == 0 then
        return
    end
    local MAX_SCENE_ID_BATCH_CHARS = 700
    local batch = {}
    for _, sourceId in ipairs(sourceIds) do
        batch[#batch + 1] = sourceId
        local candidatePayload = {
            phase = phase,
            rootName = rootName,
            bucket = bucket,
            sourceIds = batch,
        }
        local candidateJson = HttpService:JSONEncode(candidatePayload)
        if string.len(candidateJson) > MAX_SCENE_ID_BATCH_CHARS and #batch > 1 then
            table.remove(batch, #batch)
            print(marker .. suffix .. " " .. HttpService:JSONEncode({
                phase = phase,
                rootName = rootName,
                bucket = bucket,
                sourceIds = batch,
            }))
            batch = { sourceId }
        end
    end
    if #batch > 0 then
        print(marker .. suffix .. " " .. HttpService:JSONEncode({
            phase = phase,
            rootName = rootName,
            bucket = bucket,
            sourceIds = batch,
        }))
    end
end

local function emitSceneMarkers(marker, phase, rootName, radius, sceneSummary)
    local compactScene = {}
    local chunkIds = {}
    local roofCoverageByUsage = {}
    local roofCoverageByShape = {}
    local scalarValues = {}
    local propInstanceCountByKind = {}
    local ambientPropInstanceCountByKind = {}
    local treeInstanceCountBySpecies = {}
    local vegetationInstanceCountByKind = {}
    local waterSurfacePartCountByType = {}
    local waterSurfacePartCountByKind = {}
    local railReceiptCountByKind = {}
    local roadSurfacePartCountByKind = {}
    local roadSurfacePartCountBySubkind = {}
    local buildingModelCountByWallMaterial = {}
    local buildingModelCountByRoofMaterial = {}
    if typeof(sceneSummary) == "table" then
        for key, value in pairs(sceneSummary) do
            if key == "chunkIds" and typeof(value) == "table" then
                chunkIds = value
            elseif key == "buildingRoofCoverageByUsage" and typeof(value) == "table" then
                roofCoverageByUsage = value
            elseif key == "buildingRoofCoverageByShape" and typeof(value) == "table" then
                roofCoverageByShape = value
            elseif key == "propInstanceCountByKind" and typeof(value) == "table" then
                propInstanceCountByKind = value
            elseif key == "ambientPropInstanceCountByKind" and typeof(value) == "table" then
                ambientPropInstanceCountByKind = value
            elseif key == "treeInstanceCountBySpecies" and typeof(value) == "table" then
                treeInstanceCountBySpecies = value
            elseif key == "vegetationInstanceCountByKind" and typeof(value) == "table" then
                vegetationInstanceCountByKind = value
            elseif key == "waterSurfacePartCountByType" and typeof(value) == "table" then
                waterSurfacePartCountByType = value
            elseif key == "waterSurfacePartCountByKind" and typeof(value) == "table" then
                waterSurfacePartCountByKind = value
            elseif key == "railReceiptCountByKind" and typeof(value) == "table" then
                railReceiptCountByKind = value
            elseif key == "roadSurfacePartCountByKind" and typeof(value) == "table" then
                roadSurfacePartCountByKind = value
            elseif key == "roadSurfacePartCountBySubkind" and typeof(value) == "table" then
                roadSurfacePartCountBySubkind = value
            elseif key == "buildingModelCountByWallMaterial" and typeof(value) == "table" then
                buildingModelCountByWallMaterial = value
            elseif key == "buildingModelCountByRoofMaterial" and typeof(value) == "table" then
                buildingModelCountByRoofMaterial = value
            elseif key ~= "chunkIds"
                and key ~= "buildingRoofCoverageByUsage"
                and key ~= "buildingRoofCoverageByShape"
                and key ~= "propInstanceCountByKind"
                and key ~= "ambientPropInstanceCountByKind"
                and key ~= "treeInstanceCountBySpecies"
                and key ~= "vegetationInstanceCountByKind"
                and key ~= "waterSurfacePartCountByType"
                and key ~= "waterSurfacePartCountByKind"
                and key ~= "railReceiptCountByKind"
                and key ~= "roadSurfacePartCountByKind"
                and key ~= "roadSurfacePartCountBySubkind"
                and key ~= "buildingModelCountByWallMaterial"
                and key ~= "buildingModelCountByRoofMaterial"
            then
                if typeof(value) == "table" then
                    compactScene[key] = value
                else
                    scalarValues[key] = value
                end
            end
        end
    end

    print(marker .. "_CHUNKS " .. HttpService:JSONEncode({
        phase = phase,
        rootName = rootName,
        chunkIds = chunkIds,
    }))
    for key, value in pairs(scalarValues) do
        print(marker .. "_SCALAR " .. HttpService:JSONEncode({
            phase = phase,
            rootName = rootName,
            key = key,
            value = value,
        }))
    end
    for bucket, stats in pairs(roofCoverageByUsage) do
        print(marker .. "_ROOF_USAGE_BUCKET " .. HttpService:JSONEncode({
            phase = phase,
            rootName = rootName,
            bucket = bucket,
            stats = stats,
        }))
    end
    print(marker .. "_ROOF_SHAPES " .. HttpService:JSONEncode({
        phase = phase,
        rootName = rootName,
        buildingRoofCoverageByShape = roofCoverageByShape,
    }))
    for bucket, stats in pairs(propInstanceCountByKind) do
        print(marker .. "_PROP_KIND_BUCKET " .. HttpService:JSONEncode({
            phase = phase,
            rootName = rootName,
            bucket = bucket,
            stats = cloneStatsWithoutSourceIds(stats),
        }))
        emitSourceIdBatches(marker, "_PROP_KIND_IDS_BATCH", phase, rootName, bucket, stats.sourceIds)
    end
    for bucket, stats in pairs(ambientPropInstanceCountByKind) do
        print(marker .. "_AMBIENT_PROP_KIND_BUCKET " .. HttpService:JSONEncode({
            phase = phase,
            rootName = rootName,
            bucket = bucket,
            stats = stats,
        }))
    end
    for bucket, stats in pairs(treeInstanceCountBySpecies) do
        print(marker .. "_TREE_SPECIES_BUCKET " .. HttpService:JSONEncode({
            phase = phase,
            rootName = rootName,
            bucket = bucket,
            stats = cloneStatsWithoutSourceIds(stats),
        }))
        emitSourceIdBatches(marker, "_TREE_SPECIES_IDS_BATCH", phase, rootName, bucket, stats.sourceIds)
    end
    for bucket, stats in pairs(vegetationInstanceCountByKind) do
        print(marker .. "_VEGETATION_KIND_BUCKET " .. HttpService:JSONEncode({
            phase = phase,
            rootName = rootName,
            bucket = bucket,
            stats = cloneStatsWithoutSourceIds(stats),
        }))
        emitSourceIdBatches(marker, "_VEGETATION_KIND_IDS_BATCH", phase, rootName, bucket, stats.sourceIds)
    end
    for bucket, stats in pairs(waterSurfacePartCountByType) do
        print(marker .. "_WATER_TYPE_BUCKET " .. HttpService:JSONEncode({
            phase = phase,
            rootName = rootName,
            bucket = bucket,
            stats = stats,
        }))
    end
    for bucket, stats in pairs(waterSurfacePartCountByKind) do
        print(marker .. "_WATER_KIND_BUCKET " .. HttpService:JSONEncode({
            phase = phase,
            rootName = rootName,
            bucket = bucket,
            stats = cloneStatsWithoutSourceIds(stats),
        }))
        emitSourceIdBatches(marker, "_WATER_KIND_IDS_BATCH", phase, rootName, bucket, stats.sourceIds)
    end
    for bucket, stats in pairs(railReceiptCountByKind) do
        print(marker .. "_RAIL_KIND_BUCKET " .. HttpService:JSONEncode({
            phase = phase,
            rootName = rootName,
            bucket = bucket,
            stats = cloneStatsWithoutSourceIds(stats),
        }))
        emitSourceIdBatches(marker, "_RAIL_KIND_IDS_BATCH", phase, rootName, bucket, stats.sourceIds)
    end
    for bucket, stats in pairs(roadSurfacePartCountByKind) do
        print(marker .. "_ROAD_KIND_BUCKET " .. HttpService:JSONEncode({
            phase = phase,
            rootName = rootName,
            bucket = bucket,
            stats = cloneStatsWithoutSourceIds(stats),
        }))
        emitSourceIdBatches(marker, "_ROAD_KIND_IDS_BATCH", phase, rootName, bucket, stats.sourceIds)
    end
    for bucket, stats in pairs(roadSurfacePartCountBySubkind) do
        print(marker .. "_ROAD_SUBKIND_BUCKET " .. HttpService:JSONEncode({
            phase = phase,
            rootName = rootName,
            bucket = bucket,
            stats = cloneStatsWithoutSourceIds(stats),
        }))
        emitSourceIdBatches(marker, "_ROAD_SUBKIND_IDS_BATCH", phase, rootName, bucket, stats.sourceIds)
    end
    for bucket, stats in pairs(buildingModelCountByWallMaterial) do
        print(marker .. "_BUILDING_WALL_MATERIAL_BUCKET " .. HttpService:JSONEncode({
            phase = phase,
            rootName = rootName,
            bucket = bucket,
            stats = cloneStatsWithoutSourceIds(stats),
        }))
        emitSourceIdBatches(marker, "_BUILDING_WALL_MATERIAL_IDS_BATCH", phase, rootName, bucket, stats.sourceIds)
    end
    for bucket, stats in pairs(buildingModelCountByRoofMaterial) do
        print(marker .. "_BUILDING_ROOF_MATERIAL_BUCKET " .. HttpService:JSONEncode({
            phase = phase,
            rootName = rootName,
            bucket = bucket,
            stats = cloneStatsWithoutSourceIds(stats),
        }))
        emitSourceIdBatches(marker, "_BUILDING_ROOF_MATERIAL_IDS_BATCH", phase, rootName, bucket, stats.sourceIds)
    end
    print(marker .. " " .. HttpService:JSONEncode({
        phase = phase,
        rootName = rootName,
        focus = {
            x = Workspace:GetAttribute("VertigoAustinFocusX"),
            z = Workspace:GetAttribute("VertigoAustinFocusZ"),
        },
        radius = radius,
        scene = compactScene,
    }))
end
LUA
export SCENE_MARKER_LUAU

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
MEMORY_MONITOR_PID=""
MEMORY_METRICS_FILE=""
MEMORY_GUARD_FILE=""
MEMORY_LIMIT_MB="${HARNESS_MEMORY_LIMIT_MB:-4096}"
MEMORY_SAMPLE_SECONDS="${HARNESS_MEMORY_SAMPLE_SECONDS:-2}"
ALLOW_HEAVY_PREVIEW_SOURCE="${HARNESS_ALLOW_HEAVY_PREVIEW_SOURCE:-0}"
PLUGIN_SANDBOX_DIR=""
PLUGIN_SANDBOX_SOURCE_DIR=""
FOREIGN_PLUGIN_CANDIDATES=(
  "VertigoBroadcastCam.lua"
  "VertigoEditRenderer.lua"
  "VertigoEditRuntime.lua"
  "VertigoEditSync.lua"
)
ALLOWED_PLUGIN_FILES=(
  "MCPStudioPlugin.rbxm"
  "VertigoSyncPlugin.lua"
)

usage() {
  cat <<'EOF'
Usage: scripts/run_studio_harness.sh [options]

Options:
  --place PATH         Open this Roblox place file instead of starting from Studio's New template.
  --edit-wait SEC      Seconds to wait for edit-mode harness completion. Default: 20
  --play-wait SEC      Seconds to wait after entering Play mode. Default: 25
  --pattern-wait SEC   Max seconds to wait for log patterns. Default: 90
  --screenshot PATH    Capture a Studio screenshot after edit/play phases. Default: /tmp/arnis-studio-harness.png
  --no-restart         Reuse an already-running Studio session instead of relaunching it.
  --no-play            Do not enter Play mode after edit-mode harness completes.
  --keep-enabled       Leave RunAllConfig.lua enabled after the script exits.
  --edit-tests         Opt into edit-mode RunAll execution inside the harness-owned Studio session.
  --skip-edit-tests    Force edit-mode RunAll to stay disabled and only validate preview/import behavior.
  --play-tests         Also enable RunAllConfig.lua during Play mode.
  --spec-filter NAME   Run only the named Luau spec module during RunAll, for example StreamingPriority.spec.lua.
  --keep-open          Leave Roblox Studio open when the harness exits.
  --takeover           Allow the harness to take control of an already-running Studio session. By default this now means quit/relaunch for a clean harness-owned session.
  --hard-restart       Force a full Studio quit/relaunch cycle even when reuse would otherwise be allowed.
  --relaunch-play      Relaunch Studio before Play mode. Disabled by default to avoid save-dialog churn on fresh templates.
  --skip-plugin-smoke Skip the final Vertigo Sync Studio log smoke check.
  --memory-limit-mb MB Aggregate RSS budget for Roblox Studio + vsync server + MCP helper during the harness run. Set 0 to disable the fail-fast guard. Default: ${HARNESS_MEMORY_LIMIT_MB:-4096}
  --memory-sample-sec SEC  Seconds between harness memory telemetry samples. Default: ${HARNESS_MEMORY_SAMPLE_SECONDS:-2}
  HARNESS_ALLOW_HEAVY_PREVIEW_SOURCE=1  Allow the harness to run against preview sample data that looks like insane/yolo terrain density.
  --help               Show this message.

This script:
  1. Keeps edit-mode RunAll disabled by default; enable it explicitly with --edit-tests when you want tests to mutate the Studio session
  2. Opens Roblox Studio in a harness-owned session when takeover is allowed
  3. Opens an auto-built clean Arnis place when available, otherwise falls back to File > New
  4. Streams the latest Studio log to stdout
  5. Waits for the edit-mode Roblox harness to finish
  6. Optionally enters Play mode and streams runtime Austin output
  7. Restores RunAllConfig.lua on exit unless --keep-enabled is set

Play mode never inherits the test suite unless --play-tests is supplied.

Accessibility permission may be required for System Events menu automation.
EOF
}

build_clean_place() {
  local include_runtime_sample_data="${1:-true}"
  local roblox_dir="$ROOT_DIR/roblox"
  local output_suffix="edit"
  if [[ "$include_runtime_sample_data" == "true" ]]; then
    output_suffix="play"
  fi
  local output_place="$roblox_dir/out/arnis-test-clean-$output_suffix.rbxlx"
  local build_project="$roblox_dir/.harness.build.project.json"
  local serve_project="$roblox_dir/.harness.serve.project.json"

  if [[ -z "$VSYNC_BINARY" ]]; then
    return 1
  fi

  mkdir -p "$roblox_dir/out"

  local harness_project_args=(
    --default-project "$roblox_dir/default.project.json"
    --build-project "$build_project"
    --serve-project "$serve_project"
  )
  if [[ "$include_runtime_sample_data" == "true" ]]; then
    harness_project_args+=(--include-runtime-sample-data)
  fi
  python3 "$ROOT_DIR/scripts/generate_harness_projects.py" "${harness_project_args[@]}"

  HARNESS_INCLUDE_RUNTIME_SAMPLE_DATA="$include_runtime_sample_data" \
  "$VSYNC_BINARY" --root "$roblox_dir" build --project "$build_project" --output "$output_place" >/dev/null

  [[ -f "$output_place" ]]
  printf '%s\n' "$output_place"
}

resolve_vsync_binary() {
  if [[ -n "$VSYNC_BINARY" && -x "$VSYNC_BINARY" ]]; then
    VSYNC_SOURCE_REPO=0
    return 0
  fi

  if [[ -f "$VSYNC_REPO_DIR/Cargo.toml" ]] && command -v cargo >/dev/null 2>&1; then
    VSYNC_BINARY="$VSYNC_REPO_DIR/target/debug/vsync"
    VSYNC_SOURCE_REPO=1
    return 0
  fi

  if [[ -x "$HOME/.cargo/bin/vsync" ]]; then
    VSYNC_BINARY="$HOME/.cargo/bin/vsync"
    VSYNC_SOURCE_REPO=0
    return 0
  fi

  local discovered_vsync
  discovered_vsync="$(command -v vsync || true)"
  if [[ -n "$discovered_vsync" ]]; then
    VSYNC_BINARY="$discovered_vsync"
    VSYNC_SOURCE_REPO=0
    return 0
  fi

  VSYNC_BINARY=""
  VSYNC_SOURCE_REPO=0
  return 1
}

ensure_vsync_binary_fresh() {
  if ! resolve_vsync_binary; then
    return 1
  fi

  if [[ $VSYNC_SOURCE_REPO -eq 0 ]]; then
    return 0
  fi

  local binary="$VSYNC_BINARY"
  local needs_build=0
  if [[ ! -x "$binary" ]]; then
    needs_build=1
  elif find \
    "$VSYNC_REPO_DIR/src" \
    "$VSYNC_REPO_DIR/assets" \
    "$VSYNC_REPO_DIR/Cargo.toml" \
    "$VSYNC_REPO_DIR/Cargo.lock" \
    -type f -newer "$binary" -print -quit 2>/dev/null | grep -q .; then
    needs_build=1
  fi

  if [[ $needs_build -eq 1 ]]; then
    log "building vsync from adjacent repo: $VSYNC_REPO_DIR"
    cargo build --manifest-path "$VSYNC_REPO_DIR/Cargo.toml" >/dev/null
  fi

  [[ -x "$binary" ]]
}

ensure_vsync_plugin_installed() {
  if ! ensure_vsync_binary_fresh; then
    return 1
  fi

  mkdir -p "$ROBLOX_PLUGIN_DIR"

  if [[ $VSYNC_SOURCE_REPO -eq 0 ]]; then
    return 0
  fi

  local installed_plugin="$ROBLOX_PLUGIN_DIR/VertigoSyncPlugin.lua"
  local needs_install=0
  if [[ ! -f "$installed_plugin" ]]; then
    needs_install=1
  elif find \
    "$VSYNC_REPO_DIR/src" \
    "$VSYNC_REPO_DIR/assets" \
    "$VSYNC_REPO_DIR/Cargo.toml" \
    "$VSYNC_REPO_DIR/Cargo.lock" \
    -type f -newer "$installed_plugin" -print -quit 2>/dev/null | grep -q .; then
    needs_install=1
  fi

  if [[ $needs_install -eq 1 ]]; then
    log "installing Vertigo Sync plugin from adjacent repo"
    "$VSYNC_BINARY" plugin-install >/dev/null
  fi
}

auto_prepare_place() {
  local output_place=""
  local include_runtime_sample_data="true"

  if [[ $PLACE_PATH_CUSTOM -eq 1 ]]; then
    return
  fi

  if [[ $DO_PLAY -eq 0 ]]; then
    include_runtime_sample_data="false"
  fi

  if output_place="$(build_clean_place "$include_runtime_sample_data")"; then
    PLACE_PATH="$output_place"
    PLACE_PATH_CUSTOM=1
    AUTO_BUILT_PLACE=1
    log "using auto-built clean place: $PLACE_PATH"
  else
    log "clean place build unavailable; falling back to Studio New template workflow"
  fi
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
    --edit-tests)
      RUNALL_EDIT_ENABLED=1
      shift
      ;;
    --skip-edit-tests)
      RUNALL_EDIT_ENABLED=0
      shift
      ;;
    --play-tests)
      RUNALL_PLAY_ENABLED=1
      shift
      ;;
    --spec-filter)
      RUNALL_SPEC_FILTER="$2"
      shift 2
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
    --skip-plugin-smoke)
      SKIP_PLUGIN_SMOKE=1
      shift
      ;;
    --memory-limit-mb)
      MEMORY_LIMIT_MB="$2"
      shift 2
      ;;
    --memory-sample-sec)
      MEMORY_SAMPLE_SECONDS="$2"
      shift 2
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

if [[ ! -f "$RUNALL_CONFIG" ]]; then
  echo "[harness] RunAllConfig not found: $RUNALL_CONFIG" >&2
  exit 1
fi

log() {
  printf '[harness] %s\n' "$*"
}

preview_source_looks_heavy() {
  local preview_chunk_dir="$ROOT_DIR/roblox/src/ServerScriptService/StudioPreview/AustinPreviewManifestChunks"
  if [[ ! -d "$preview_chunk_dir" ]]; then
    return 1
  fi
  if rg -q 'cellSizeStuds = 1' "$preview_chunk_dir"/*.lua 2>/dev/null; then
    return 0
  fi
  return 1
}

if [[ "$ALLOW_HEAVY_PREVIEW_SOURCE" != "1" ]] && preview_source_looks_heavy; then
  echo "[harness] preview source appears to be insane/yolo-grade terrain data; regenerate lighter Austin preview assets or rerun with HARNESS_ALLOW_HEAVY_PREVIEW_SOURCE=1" >&2
  exit 1
fi

sample_harness_memory_json() {
  python3 - "$VSYNC_SERVER_PID" <<'PY'
import json
import subprocess
import sys

vsync_pid_raw = sys.argv[1].strip()
vsync_pid = int(vsync_pid_raw) if vsync_pid_raw.isdigit() else None

try:
    ps_output = subprocess.check_output(["ps", "axo", "pid=,rss=,comm=,args="], text=True)
except Exception:
    print(json.dumps({"studio_kb": 0, "vsync_kb": 0, "mcp_kb": 0, "total_kb": 0}))
    raise SystemExit(0)

studio_pids = set()
try:
    studio_pid_output = subprocess.check_output(["pgrep", "-x", "RobloxStudio"], text=True)
    for raw_pid in studio_pid_output.splitlines():
        raw_pid = raw_pid.strip()
        if raw_pid.isdigit():
            studio_pids.add(int(raw_pid))
except Exception:
    pass

studio_kb = 0
vsync_kb = 0
mcp_kb = 0
for raw_line in ps_output.splitlines():
    line = raw_line.strip()
    if not line:
        continue
    parts = line.split(None, 3)
    if len(parts) < 4:
        continue
    pid_raw, rss_raw, comm, args = parts
    try:
        pid = int(pid_raw)
        rss_kb = int(rss_raw)
    except ValueError:
        continue
    if pid in studio_pids or comm == "RobloxStudio" or "RobloxStudio.app/Contents/MacOS/RobloxStudio" in args:
        studio_kb += rss_kb
    if vsync_pid is not None and pid == vsync_pid:
        vsync_kb += rss_kb
    if "rbx-studio-mcp" in args:
        mcp_kb += rss_kb

print(
    json.dumps(
        {
            "studio_kb": studio_kb,
            "vsync_kb": vsync_kb,
            "mcp_kb": mcp_kb,
            "total_kb": studio_kb + vsync_kb + mcp_kb,
        },
        separators=(",", ":"),
    )
)
PY
}

sample_harness_host_probe_json() {
  local sample_json
  sample_json="$(sample_harness_memory_json 2>/dev/null || printf '')"
  python3 - "$sample_json" "$MEMORY_LIMIT_MB" <<'PY'
import json
import sys

raw_sample = sys.argv[1].strip()
sample = json.loads(raw_sample) if raw_sample else {}
limit_mb = float(sys.argv[2]) if sys.argv[2].strip() else 0.0
total_kb = int(sample.get("total_kb", 0) or 0)
limit_bytes = int(limit_mb * 1024 * 1024) if limit_mb > 0 else 0
used_bytes = total_kb * 1024
available_bytes = max(0, limit_bytes - used_bytes) if limit_bytes > 0 else None
pressure_level = (used_bytes / limit_bytes) if limit_bytes > 0 else None

print(
    json.dumps(
        {
            "availableBytes": available_bytes,
            "pressureLevel": pressure_level,
            "limitBytes": limit_bytes if limit_bytes > 0 else None,
            "usedBytes": used_bytes,
        },
        separators=(",", ":"),
    )
)
PY
}

start_memory_monitor() {
  if [[ -n "$MEMORY_MONITOR_PID" ]]; then
    return
  fi

  MEMORY_METRICS_FILE="$(mktemp)"
  MEMORY_GUARD_FILE="$(mktemp)"
  local limit_mb="$MEMORY_LIMIT_MB"
  local sample_seconds="$MEMORY_SAMPLE_SECONDS"
  local parent_pid="$$"

  (
    while true; do
      local sample_json=""
      sample_json="$(sample_harness_memory_json 2>/dev/null || printf '')"
      if [[ -n "$sample_json" ]]; then
        local sample_line=""
        sample_line="$(python3 - "$sample_json" <<'PY'
import json
import sys

sample = json.loads(sys.argv[1])
print(
    f"{sample.get('total_kb', 0)},{sample.get('studio_kb', 0)},{sample.get('vsync_kb', 0)},{sample.get('mcp_kb', 0)}"
)
PY
)"
        printf '%s\n' "$sample_line" >>"$MEMORY_METRICS_FILE"

        if [[ "$limit_mb" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
          python3 - "$sample_json" "$limit_mb" "$MEMORY_GUARD_FILE" <<'PY'
import json
import sys
from pathlib import Path

sample = json.loads(sys.argv[1])
limit_mb = float(sys.argv[2])
guard_path = Path(sys.argv[3])
if limit_mb <= 0:
    raise SystemExit(0)

total_mb = sample.get("total_kb", 0) / 1024
if total_mb <= limit_mb:
    raise SystemExit(0)

guard_path.write_text(
    "aggregate harness RSS exceeded budget: "
    f"total={total_mb:.1f}MB limit={limit_mb:.1f}MB "
    f"studio={sample.get('studio_kb', 0) / 1024:.1f}MB "
    f"vsync={sample.get('vsync_kb', 0) / 1024:.1f}MB "
    f"mcp={sample.get('mcp_kb', 0) / 1024:.1f}MB",
    encoding="utf-8",
)
raise SystemExit(1)
PY
          local breach_exit=$?
          if [[ $breach_exit -ne 0 ]]; then
            kill -TERM "$parent_pid" >/dev/null 2>&1 || true
            exit 0
          fi
        fi
      fi

      sleep "$sample_seconds"
    done
  ) &
  MEMORY_MONITOR_PID="$!"
}

stop_memory_monitor() {
  if [[ -n "$MEMORY_MONITOR_PID" ]]; then
    kill "$MEMORY_MONITOR_PID" >/dev/null 2>&1 || true
    wait "$MEMORY_MONITOR_PID" >/dev/null 2>&1 || true
    MEMORY_MONITOR_PID=""
  fi
}

summarize_memory_monitor() {
  if [[ -z "$MEMORY_METRICS_FILE" || ! -f "$MEMORY_METRICS_FILE" ]]; then
    return
  fi

  python3 - "$MEMORY_METRICS_FILE" <<'PY'
from pathlib import Path
import sys

metrics_path = Path(sys.argv[1])
peak_total = 0
peak_studio = 0
peak_vsync = 0
peak_mcp = 0
for line in metrics_path.read_text(encoding="utf-8").splitlines():
    if not line.strip():
        continue
    total_kb, studio_kb, vsync_kb, mcp_kb = (int(part) for part in line.split(",", 3))
    peak_total = max(peak_total, total_kb)
    peak_studio = max(peak_studio, studio_kb)
    peak_vsync = max(peak_vsync, vsync_kb)
    peak_mcp = max(peak_mcp, mcp_kb)

print(
    "[harness] memory peaks "
    f"total={peak_total / 1024:.1f}MB "
    f"studio={peak_studio / 1024:.1f}MB "
    f"vsync={peak_vsync / 1024:.1f}MB "
    f"mcp={peak_mcp / 1024:.1f}MB"
)
PY

  if [[ -f "$MEMORY_GUARD_FILE" && -s "$MEMORY_GUARD_FILE" ]]; then
    log "$(cat "$MEMORY_GUARD_FILE")"
  fi

  rm -f "$MEMORY_METRICS_FILE" "$MEMORY_GUARD_FILE"
  MEMORY_METRICS_FILE=""
  MEMORY_GUARD_FILE=""
}

capture_preview_telemetry_artifacts() {
  if [[ -z "$VSYNC_SERVER_URL" ]]; then
    return 0
  fi

  local preview_telemetry_dir="${ARNIS_PREVIEW_TELEMETRY_DIR:-/tmp}"
  mkdir -p "$preview_telemetry_dir"

  local plugin_state_json="$preview_telemetry_dir/arnis-preview-plugin-state.json"
  local telemetry_summary_txt="$preview_telemetry_dir/arnis-preview-telemetry-summary.txt"

  if ! curl -sf "$VSYNC_SERVER_URL/plugin/state" -o "$plugin_state_json"; then
    log "preview telemetry unavailable from $VSYNC_SERVER_URL/plugin/state"
    rm -f "$plugin_state_json" "$telemetry_summary_txt"
    return 0
  fi

  python3 - "$plugin_state_json" "$telemetry_summary_txt" <<'PY'
from pathlib import Path
import json
import sys

plugin_state_path = Path(sys.argv[1])
summary_path = Path(sys.argv[2])
data = json.loads(plugin_state_path.read_text(encoding="utf-8"))
runtime = data.get("preview_runtime") or {}
project = data.get("preview_project") or {}
project_counters = project.get("counters") or {}
project_chunks = project.get("chunkTotals") or {}

summary = (
    "runtime="
    f"schedule={runtime.get('schedule_count', 0)} "
    f"run={runtime.get('run_count', 0)} "
    f"success={runtime.get('success_count', 0)} "
    f"failure={runtime.get('failure_count', 0)} "
    f"skip={runtime.get('skip_count', 0)} "
    f"retry={runtime.get('auto_retry_count', 0)} "
    f"busy={runtime.get('queued_while_busy_count', 0)}; "
    "project="
    f"build={project_counters.get('build_scheduled', 0)} "
    f"sync_complete={project_counters.get('sync_complete', 0)} "
    f"sync_cancelled={project_counters.get('sync_cancelled', 0)} "
    f"state_apply_succeeded={project_counters.get('state_apply_succeeded', 0)} "
    f"state_apply_failed={project_counters.get('state_apply_failed', 0)} "
    f"imported={project_chunks.get('imported', 0)} "
    f"skipped={project_chunks.get('skipped', 0)} "
    f"unloaded={project_chunks.get('unloaded', 0)}"
)

summary_path.write_text(summary, encoding="utf-8")
print(summary)
PY

  log "preview telemetry saved: $plugin_state_json"
  if [[ -f "$telemetry_summary_txt" ]]; then
    log "preview telemetry summary: $(cat "$telemetry_summary_txt")"
  fi
}

latest_studio_log() {
  ls -t "$LOG_DIR"/*_Studio_*_last.log 2>/dev/null | head -n 1 || true
}

studio_pids() {
  pgrep -x "RobloxStudio" 2>/dev/null || true
}

studio_session_status_json() {
  python3 "$STUDIO_UI_CONTROL" get-session-status 2>/dev/null || true
}

studio_dump_ui_json() {
  python3 "$STUDIO_UI_CONTROL" dump-ui 2>/dev/null || true
}

studio_session_status_value() {
  local field="$1"
  python3 "$STUDIO_UI_CONTROL" get-session-status-value "$field" 2>/dev/null || true
}

restore_runall_config() {
  if [[ -n "$RUNALL_BACKUP" && -f "$RUNALL_BACKUP" && $KEEP_RUNALL_ENABLED -eq 0 ]]; then
    cp "$RUNALL_BACKUP" "$RUNALL_CONFIG"
  fi
  if [[ -n "$RUNALL_BACKUP" && -f "$RUNALL_BACKUP" ]]; then
    rm -f "$RUNALL_BACKUP"
  fi
}

restore_foreign_plugins() {
  if [[ -z "$PLUGIN_SANDBOX_DIR" || -z "$PLUGIN_SANDBOX_SOURCE_DIR" ]]; then
    return
  fi

  rm -rf "$ROBLOX_PLUGIN_DIR"
  mv "$PLUGIN_SANDBOX_SOURCE_DIR" "$ROBLOX_PLUGIN_DIR"
  rmdir "$PLUGIN_SANDBOX_DIR" >/dev/null 2>&1 || true
  PLUGIN_SANDBOX_DIR=""
  PLUGIN_SANDBOX_SOURCE_DIR=""
}

quarantine_foreign_plugins() {
  if [[ ! -d "$ROBLOX_PLUGIN_DIR" || -n "$PLUGIN_SANDBOX_DIR" ]]; then
    return
  fi

  local plugin_name=""
  local kept_count=0
  local quarantined_count=0
  local sandbox_dir
  local sandbox_source_dir
  sandbox_dir="$(mktemp -d)"
  sandbox_source_dir="$sandbox_dir/original_plugins"
  mv "$ROBLOX_PLUGIN_DIR" "$sandbox_source_dir"
  mkdir -p "$ROBLOX_PLUGIN_DIR"

  for plugin_name in "${ALLOWED_PLUGIN_FILES[@]}"; do
    if [[ -f "$sandbox_source_dir/$plugin_name" ]]; then
      cp "$sandbox_source_dir/$plugin_name" "$ROBLOX_PLUGIN_DIR/$plugin_name"
      kept_count=$((kept_count + 1))
    fi
  done

  for plugin_name in "${FOREIGN_PLUGIN_CANDIDATES[@]}"; do
    if [[ -f "$sandbox_source_dir/$plugin_name" ]]; then
      quarantined_count=$((quarantined_count + 1))
    fi
  done

  PLUGIN_SANDBOX_DIR="$sandbox_dir"
  PLUGIN_SANDBOX_SOURCE_DIR="$sandbox_source_dir"
  log "sandboxed Roblox plugins for this harness run: kept $kept_count allowed plugin(s), quarantined $quarantined_count foreign Vertigo edit plugin(s)"
  if [[ -n "$(studio_pids)" ]]; then
    log "sandboxed plugins only affect Studio after restart; attached sessions may still have them loaded"
  fi
}

purge_harness_autosaves() {
  if [[ ! -d "$ROBLOX_AUTOSAVE_DIR" ]]; then
    return
  fi

  local purged_count=0
  local pattern=""
  local autosave=""
  local patterns=(
    "arnis-test-clean_AutoRecovery_*.rbxlx"
    "arnis-test-clean_AutoRecovery_*.rbxl"
    "arnis-test_AutoRecovery_*.rbxlx"
    "arnis-test_AutoRecovery_*.rbxl"
  )

  for pattern in "${patterns[@]}"; do
    for autosave in "$ROBLOX_AUTOSAVE_DIR"/$pattern; do
      if [[ -e "$autosave" ]]; then
        rm -f "$autosave"
        purged_count=$((purged_count + 1))
      fi
    done
  done

  if [[ $purged_count -gt 0 ]]; then
    log "purged $purged_count harness-owned Studio autosave(s)"
  fi
}

set_runall_config_modes() {
  local edit_enabled="$1"
  local play_enabled="$2"
  python3 - "$RUNALL_CONFIG" "$edit_enabled" "$play_enabled" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
edit_enabled = sys.argv[2].lower() == "true"
play_enabled = sys.argv[3].lower() == "true"
text = path.read_text(encoding="utf-8")
edit_markers = ("runInEditMode = true", "runInEditMode = false")
play_markers = ("runInPlayMode = true", "runInPlayMode = false")

for old in edit_markers:
    if old in text:
        text = text.replace(old, f"runInEditMode = {'true' if edit_enabled else 'false'}", 1)
        break
else:
    raise SystemExit("RunAllConfig edit-mode toggle field not found")

for old in play_markers:
    if old in text:
        text = text.replace(old, f"runInPlayMode = {'true' if play_enabled else 'false'}", 1)
        break
else:
    raise SystemExit("RunAllConfig play-mode toggle field not found")

path.write_text(text, encoding="utf-8")
PY
}

set_runall_config_filter() {
  local spec_filter="$1"
  python3 - "$RUNALL_CONFIG" "$spec_filter" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
spec_filter = sys.argv[2]
text = path.read_text(encoding="utf-8")
marker = 'specNameFilter = ""'

if marker not in text:
    for line in text.splitlines():
        if line.strip().startswith("specNameFilter = "):
            marker = line
            break
    else:
        raise SystemExit("RunAllConfig spec filter field not found")

replacement = f"specNameFilter = {spec_filter!r}"
text = text.replace(marker, replacement, 1)
path.write_text(text, encoding="utf-8")
PY
}

disable_runall_entry() {
  set_runall_config_modes false false
}

cleanup() {
  local exit_code="${1:-0}"
  if [[ $CLEANUP_RUNNING -eq 1 ]]; then
    return
  fi
  CLEANUP_RUNNING=1
  stop_log_pipe
  stop_memory_monitor
  if [[ -n "$LOG_SLICE_FILE" && -f "$LOG_SLICE_FILE" ]]; then
    rm -f "$LOG_SLICE_FILE"
  fi
  local session_status="not_running"
  session_status="$(studio_session_status_value status 2>/dev/null || printf 'not_running')"
  local cleanup_decision=""
  cleanup_decision="$(python3 "$STUDIO_HARNESS_POLICY" cleanup-close \
    --exit-code "$exit_code" \
    --close-on-exit "$CLOSE_ON_EXIT" \
    --harness-owns-studio "$HARNESS_OWNS_STUDIO" \
    --session-status "$session_status" 2>/dev/null || true)"
  local should_close="false"
  local cleanup_reason="policy_error"
  if [[ -n "$cleanup_decision" ]]; then
    should_close="$(python3 -c 'import json,sys; print(str(bool(json.loads(sys.stdin.read()).get("should_close"))).lower())' <<<"$cleanup_decision" 2>/dev/null || printf 'false')"
    cleanup_reason="$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read()).get("reason","policy_error"))' <<<"$cleanup_decision" 2>/dev/null || printf 'policy_error')"
  fi

  if [[ "$should_close" == "true" ]]; then
    quit_studio
  elif [[ $CLOSE_ON_EXIT -eq 1 && $HARNESS_OWNS_STUDIO -eq 1 ]]; then
    log "preserving harness-owned Studio session on exit (reason=$cleanup_reason status=$session_status exit=$exit_code)"
  fi
  summarize_memory_monitor
  stop_vsync_server
  restore_runall_config
  restore_foreign_plugins
}

trap 'cleanup "$?"' EXIT
trap 'exit 130' INT TERM

enable_runall_entry() {
  local edit_enabled="true"
  local play_enabled="false"
  if [[ $RUNALL_EDIT_ENABLED -eq 0 || -n "$MCP_BINARY" ]]; then
    edit_enabled="false"
  fi
  if [[ $RUNALL_PLAY_ENABLED -eq 1 ]]; then
    play_enabled="true"
  fi
  RUNALL_BACKUP="$(mktemp)"
  cp "$RUNALL_CONFIG" "$RUNALL_BACKUP"
  set_runall_config_modes "$edit_enabled" "$play_enabled"
  set_runall_config_filter "$RUNALL_SPEC_FILTER"
}

can_run_runall_entry_edit_fallback() {
  [[ $RUNALL_EDIT_ENABLED -eq 1 ]] || return 1
  [[ -n "$RUNALL_SPEC_FILTER" ]] || return 1
  if [[ "$RUNALL_SPEC_FILTER" == *Preview* ]]; then
    return 1
  fi
  return 0
}

quit_studio() {
  local session_status="not_running"
  session_status="$(studio_session_status_value status 2>/dev/null || printf 'not_running')"
  local log_indicates_play="false"
  if studio_log_indicates_play_session; then
    log_indicates_play="true"
  fi
  local stop_decision=""
  stop_decision="$(python3 "$STUDIO_HARNESS_POLICY" should-stop-play \
    --session-status "$session_status" \
    --log-indicates-play "$log_indicates_play" 2>/dev/null || true)"
  local should_stop_play="false"
  if [[ -n "$stop_decision" ]]; then
    should_stop_play="$(python3 -c 'import json,sys; print(str(bool(json.loads(sys.stdin.read()).get("should_stop"))).lower())' <<<"$stop_decision" 2>/dev/null || printf 'false')"
  fi
  if [[ "$should_stop_play" == "true" ]]; then
    stop_play_mode || true
    wait_for_session_status "ready_edit,start_page,blocked_dialog,not_running,transitioning" 20 || true
    session_status="$(studio_session_status_value status 2>/dev/null || printf 'not_running')"
  fi

  local graceful_quit_decision=""
  graceful_quit_decision="$(python3 "$STUDIO_HARNESS_POLICY" should-graceful-quit \
    --session-status "$session_status" 2>/dev/null || true)"
  local should_graceful_quit="false"
  if [[ -n "$graceful_quit_decision" ]]; then
    should_graceful_quit="$(python3 -c 'import json,sys; print(str(bool(json.loads(sys.stdin.read()).get("should_quit"))).lower())' <<<"$graceful_quit_decision" 2>/dev/null || printf 'false')"
  fi
  if [[ "$should_graceful_quit" == "true" ]]; then
    python3 "$STUDIO_UI_CONTROL" quit >/dev/null 2>&1 || true
  else
    log "skipping graceful Studio quit while session is still unstable (status=$session_status)"
  fi

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

  local stable_checks=0
  local waited_for_not_running=0
  while [[ $waited_for_not_running -lt 10 ]]; do
    local session_status
    session_status="$(studio_session_status_value status)"
    if [[ "$session_status" == "not_running" ]]; then
      stable_checks=$((stable_checks + 1))
      if [[ $stable_checks -ge 2 ]]; then
        break
      fi
    else
      stable_checks=0
    fi
    sleep 1
    waited_for_not_running=$((waited_for_not_running + 1))
  done
}

force_quit_studio() {
  dismiss_startup_dialogs || true
  python3 "$STUDIO_UI_CONTROL" dismiss-dont-save >/dev/null 2>&1 || true

  local waited=0
  while [[ -n "$(studio_pids)" && $waited -lt 2 ]]; do
    sleep 1
    waited=$((waited + 1))
  done

  if [[ -n "$(studio_pids)" ]]; then
    python3 "$STUDIO_UI_CONTROL" force-quit >/dev/null 2>&1 || true
  fi

  waited=0
  while [[ -n "$(studio_pids)" && $waited -lt 10 ]]; do
    sleep 1
    waited=$((waited + 1))
  done

  if [[ -n "$(studio_pids)" ]]; then
    return 1
  fi

  return 0
}

studio_opened_target_place() {
  if [[ $PLACE_PATH_CUSTOM -eq 0 ]]; then
    local status
    status="$(studio_session_status_value status)"
    [[ -n "$status" && "$status" != "not_running" ]]
    return
  fi

  local front_window
  front_window="$(studio_session_status_value front_window)"
  local place_basename
  place_basename="$(basename "$PLACE_PATH")"
  [[ -n "$front_window" && "$front_window" == *"$place_basename"* ]]
}

open_studio() {
  HARNESS_OWNS_STUDIO=1
  local attempts=0
  while [[ $attempts -lt 5 ]]; do
    local session_status
    session_status="$(studio_session_status_value status)"
    if [[ "$session_status" == "blocked_dialog" ]]; then
      dismiss_startup_dialogs
      python3 "$STUDIO_UI_CONTROL" dismiss-dont-save >/dev/null 2>&1 || true
      sleep 1
      session_status="$(studio_session_status_value status)"
    fi
    if [[ "$session_status" == "transitioning" ]]; then
      sleep 2
      attempts=$((attempts + 1))
      continue
    fi

    if [[ $PLACE_PATH_CUSTOM -eq 1 ]]; then
      if [[ -d "$APP_PATH" ]]; then
        if open -a "$APP_PATH" "$PLACE_PATH"; then
          local waited_for_target=0
          while [[ $waited_for_target -lt 15 ]]; do
            if studio_opened_target_place; then
              return 0
            fi
            dismiss_startup_dialogs
            sleep 1
            waited_for_target=$((waited_for_target + 1))
          done
        fi
      elif open -b "$APP_BUNDLE_ID" "$PLACE_PATH"; then
        local waited_for_target=0
        while [[ $waited_for_target -lt 15 ]]; do
          if studio_opened_target_place; then
            return 0
          fi
          dismiss_startup_dialogs
          sleep 1
          waited_for_target=$((waited_for_target + 1))
        done
      fi
    else
      if [[ -d "$APP_PATH" ]]; then
        if open -a "$APP_PATH"; then
          local waited_for_target=0
          while [[ $waited_for_target -lt 15 ]]; do
            if studio_opened_target_place; then
              return 0
            fi
            dismiss_startup_dialogs
            sleep 1
            waited_for_target=$((waited_for_target + 1))
          done
        fi
      elif open -b "$APP_BUNDLE_ID"; then
        local waited_for_target=0
        while [[ $waited_for_target -lt 15 ]]; do
          if studio_opened_target_place; then
            return 0
          fi
          dismiss_startup_dialogs
          sleep 1
          waited_for_target=$((waited_for_target + 1))
        done
      fi
    fi

    attempts=$((attempts + 1))
    sleep "$STUDIO_RELAUNCH_COOLDOWN_SECONDS"
  done

  return 1
}

wait_for_new_log() {
  local previous_log="$1"
  local started_at="$2"
  local waited=0
  while [[ $waited -lt $MCP_READY_WAIT_SECONDS ]]; do
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
    re.compile(r"127\.0\.0\.1 port 7575", re.IGNORECASE),
    re.compile(r"http://127\.0\.0\.1:7575/snapshot", re.IGNORECASE),
    re.compile(r"HttpError: ConnectFail", re.IGNORECASE),
    re.compile(r"\[VertigoSync\] Snapshot sync failed \(requested\): HttpError: ConnectFail", re.IGNORECASE),
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

resolve_vsync_server_url() {
  if [[ -n "$VSYNC_SERVER_URL" ]]; then
    return 0
  fi

  VSYNC_SERVER_URL="$(python3 - "$ROOT_DIR/roblox/default.project.json" <<'PY'
import json
import sys
from pathlib import Path

project_path = Path(sys.argv[1])
data = json.loads(project_path.read_text(encoding="utf-8"))
workspace = data.get("tree", {}).get("Workspace") or {}
attributes = workspace.get("$attributes") or {}
server_url = attributes.get("VertigoSyncServerUrl")
if isinstance(server_url, str) and server_url:
    print(server_url)
    raise SystemExit(0)

address = data.get("serveAddress") or "127.0.0.1"
port = data.get("servePort") or 7575
print(f"http://{address}:{port}")
PY
)"

  [[ -n "$VSYNC_SERVER_URL" ]]
}

vsync_project_endpoint_ready() {
  resolve_vsync_server_url || return 1
  curl -sf "$VSYNC_SERVER_URL/project" >/dev/null 2>&1
}

vsync_server_port() {
  resolve_vsync_server_url || return 1
  python3 - "$VSYNC_SERVER_URL" <<'PY'
from urllib.parse import urlparse
import sys

parsed = urlparse(sys.argv[1])
port = parsed.port
if port is None:
    port = 443 if parsed.scheme == "https" else 80
print(port)
PY
}

should_reuse_vsync_server() {
  [[ $DO_RESTART -eq 0 && $HARD_RESTART -eq 0 && $ALLOW_TAKEOVER -eq 1 ]]
}

terminate_stale_vsync_listener() {
  local port=""
  port="$(vsync_server_port)" || return 1

  local listener_pids=""
  listener_pids="$(lsof -nP -iTCP:"$port" -sTCP:LISTEN -t 2>/dev/null | tr '\n' ' ' || true)"
  if [[ -z "$listener_pids" ]]; then
    return 0
  fi

  local pid=""
  for pid in $listener_pids; do
    local command_line=""
    command_line="$(ps -p "$pid" -o command= 2>/dev/null || true)"
    if [[ "$command_line" != *vsync*serve* ]]; then
      log "refusing to kill non-vsync listener on port $port (pid=$pid cmd=$command_line)"
      return 1
    fi
    if kill -0 "$pid" >/dev/null 2>&1; then
      log "stopping stale Vertigo Sync listener on port $port (pid=$pid)"
      kill "$pid" >/dev/null 2>&1 || true
      sleep 1
      if kill -0 "$pid" >/dev/null 2>&1; then
        kill -9 "$pid" >/dev/null 2>&1 || true
      fi
    fi
  done
}

stop_vsync_server() {
  if [[ -n "$VSYNC_SERVER_PID" ]]; then
    if kill -0 "$VSYNC_SERVER_PID" >/dev/null 2>&1; then
      kill "$VSYNC_SERVER_PID" >/dev/null 2>&1 || true
      wait "$VSYNC_SERVER_PID" >/dev/null 2>&1 || true
    fi
  fi
  VSYNC_SERVER_PID=""

  if [[ -n "$VSYNC_SERVER_LOG" && -f "$VSYNC_SERVER_LOG" ]]; then
    rm -f "$VSYNC_SERVER_LOG"
  fi
  VSYNC_SERVER_LOG=""
}

ensure_vsync_server_running() {
  local roblox_dir="$ROOT_DIR/roblox"
  local serve_project="$roblox_dir/.harness.serve.project.json"

  if ! ensure_vsync_binary_fresh; then
    log "vsync binary unavailable; cannot start local sync server"
    return 1
  fi

  resolve_vsync_server_url || {
    log "failed to resolve Vertigo Sync server URL from default.project.json"
    return 1
  }

  if should_reuse_vsync_server && vsync_project_endpoint_ready; then
    log "reusing existing Vertigo Sync server at $VSYNC_SERVER_URL"
    return 0
  fi

  terminate_stale_vsync_listener || {
    log "failed to clear stale Vertigo Sync listener before starting a fresh server"
    return 1
  }

  VSYNC_SERVER_LOG="$(mktemp -t arnis-vsync-serve)"
  (
    cd "$roblox_dir"
    if [[ -f "$serve_project" ]]; then
      exec "$VSYNC_BINARY" serve --project "$serve_project"
    fi
    exec "$VSYNC_BINARY" serve --project default.project.json
  ) >"$VSYNC_SERVER_LOG" 2>&1 &
  VSYNC_SERVER_PID=$!
  log "starting Vertigo Sync server at $VSYNC_SERVER_URL (pid=$VSYNC_SERVER_PID)"

  local waited=0
  while [[ $waited -lt $PATTERN_WAIT_SECONDS ]]; do
    if vsync_project_endpoint_ready; then
      log "Vertigo Sync server is ready at $VSYNC_SERVER_URL"
      return 0
    fi
    if ! kill -0 "$VSYNC_SERVER_PID" >/dev/null 2>&1; then
      log "Vertigo Sync server exited before /project became ready"
      if [[ -f "$VSYNC_SERVER_LOG" ]]; then
        log "Vertigo Sync server log tail: $(tail -n 5 "$VSYNC_SERVER_LOG" | tr '\n' ' ' | sed 's/[[:space:]]\\+/ /g')"
      fi
      stop_vsync_server
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done

  log "timed out waiting for Vertigo Sync /project readiness at $VSYNC_SERVER_URL"
  if [[ -f "$VSYNC_SERVER_LOG" ]]; then
    log "Vertigo Sync server log tail: $(tail -n 5 "$VSYNC_SERVER_LOG" | tr '\n' ' ' | sed 's/[[:space:]]\\+/ /g')"
  fi
  stop_vsync_server
  return 1
}

wait_for_vsync_edit_readiness() {
  local readiness_target="${VSYNC_EDIT_READINESS_TARGET:-preview}"
  local readiness_timeout="${VSYNC_READINESS_TIMEOUT:-$PATTERN_WAIT_SECONDS}"

  VSYNC_SERVER_URL="$VSYNC_SERVER_URL" \
  VSYNC_READINESS_TARGET="$readiness_target" \
  VSYNC_READINESS_TIMEOUT="$readiness_timeout" \
  python3 - <<'PY'
import json
import os
import sys

sys.path.insert(0, '/Users/adpena/Projects/arnis-roblox/scripts')
from studio_harness_policy import wait_for_readiness

record = wait_for_readiness(
    os.environ["VSYNC_SERVER_URL"],
    os.environ["VSYNC_READINESS_TARGET"],
    int(os.environ["VSYNC_READINESS_TIMEOUT"]),
)
print(json.dumps(record, separators=(",", ":")))
PY
}

recover_vsync_server_for_edit_readiness() {
  if vsync_project_endpoint_ready; then
    return 0
  fi

  log "Vertigo Sync server is unreachable during edit readiness; restarting it before retry"
  stop_vsync_server
  ensure_vsync_server_running || {
    log "failed to restart Vertigo Sync server during edit readiness recovery"
    return 1
  }

  wait_for_log_pattern "\\[VertigoSync\\] Snapshot reconciled|\\[VertigoSync\\] Plugin initialized" "$PATTERN_WAIT_SECONDS" || {
    log "Vertigo Sync plugin did not emit initialization markers after server recovery; continuing with best effort"
  }

  return 0
}

wait_for_studio_process() {
  local waited=0
  while [[ $waited -lt $PATTERN_WAIT_SECONDS ]]; do
    dismiss_startup_dialogs
    local status
    status="$(studio_session_status_value status)"
    if [[ -n "$status" && "$status" != "not_running" ]]; then
      return 0
    fi
    sleep 1
    waited=$((waited + 1))
  done
  return 1
}

wait_for_session_status() {
  local desired_statuses_csv="$1"
  local timeout_seconds="$2"
  local waited=0
  local blocked_logged=0
  while [[ $waited -lt $timeout_seconds ]]; do
    dismiss_startup_dialogs
    local status
    status="$(studio_session_status_value status)"
    if [[ -n "$status" ]]; then
      local desired
      IFS=',' read -r -a desired <<< "$desired_statuses_csv"
      local candidate=""
      for candidate in "${desired[@]}"; do
        if [[ "$status" == "$candidate" ]]; then
          return 0
        fi
      done
      if [[ "$status" == "blocked_dialog" && $blocked_logged -eq 0 ]]; then
        log "Studio blocked dialog snapshot: $(studio_dump_ui_json)"
        blocked_logged=1
      fi
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

run_edit_actions_via_runall_entry() {
  can_run_runall_entry_edit_fallback || return 1

  log "enabling RunAllEntry fallback for isolated edit spec: $RUNALL_SPEC_FILTER"
  set_runall_config_filter "$RUNALL_SPEC_FILTER"
  set_runall_config_modes true false

  if wait_for_log_pattern "Filtering tests to spec:|Running tests:|TestEZ tests complete|Tests failed" "$EDIT_WAIT_SECONDS"; then
    return 0
  fi

  log "RunAllEntry fallback did not emit edit-mode test markers before timeout"
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
  if wait_for_log_pattern "ARNIS_MCP_EDIT_ACTION|TestEZ tests complete|Tests failed|\\[AustinPreviewBuilder\\] sync complete" "$PATTERN_WAIT_SECONDS"; then
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
  studio_session_status_json
}

wait_for_editor_ready() {
  local timeout="${1:-45}"
  python3 "$STUDIO_WORKFLOW" ensure-editor-ready --timeout "$timeout" >/dev/null 2>&1
}

wait_for_playing() {
  local timeout="${1:-20}"
  python3 "$STUDIO_WORKFLOW" ensure-playing --timeout "$timeout" >/dev/null 2>&1
}

attached_session_is_really_playing() {
  if [[ -z "$ACTIVE_LOG" || ! -f "$ACTIVE_LOG" ]]; then
    return 1
  fi

  local status=""
  status="$(studio_session_status_value status)"
  if [[ "$status" != "ready_play" ]]; then
    return 1
  fi

  if studio_log_indicates_play_session; then
    return 0
  fi

  return 1
}

studio_log_indicates_play_session() {
  local log_probe_file=""
  if [[ -n "$LOG_SLICE_FILE" && -f "$LOG_SLICE_FILE" ]]; then
    log_probe_file="$LOG_SLICE_FILE"
  elif [[ -n "$ACTIVE_LOG" && -f "$ACTIVE_LOG" ]]; then
    log_probe_file="$ACTIVE_LOG"
  else
    return 1
  fi

  if rg -q "PlaceStateTransitionStatus becomes StartingPlayTest|\\[BootstrapAustin\\]|\\[RunAustin\\]|ARNIS_MCP_PLAY|StudioGameStateType_Client" "$log_probe_file"; then
    return 0
  fi

  return 1
}

edit_action_completed_successfully_in_log() {
  local log_probe_file=""
  if [[ -n "$LOG_SLICE_FILE" && -f "$LOG_SLICE_FILE" ]]; then
    log_probe_file="$LOG_SLICE_FILE"
  elif [[ -n "$ACTIVE_LOG" && -f "$ACTIVE_LOG" ]]; then
    log_probe_file="$ACTIVE_LOG"
  else
    return 1
  fi

  python3 - "$log_probe_file" "$STUDIO_HARNESS_POLICY" <<'PY' >/dev/null 2>&1
import json
import sys
from pathlib import Path

log_path = Path(sys.argv[1])
policy_path = Path(sys.argv[2])
sys.path.insert(0, str(policy_path.parent))
from studio_harness_policy import is_successful_edit_action_payload

marker = "ARNIS_MCP_EDIT_ACTION "
last_payload = None

with log_path.open("r", encoding="utf-8", errors="replace") as handle:
    for raw_line in handle:
        if marker not in raw_line:
            continue
        payload_text = raw_line.split(marker, 1)[1].strip()
        try:
            last_payload = json.loads(payload_text)
        except json.JSONDecodeError:
            continue

if not is_successful_edit_action_payload(last_payload):
    raise SystemExit(1)
PY
}

validate_preview_rebuild_behavior() {
  local log_probe_file=""
  if [[ -n "$LOG_SLICE_FILE" && -f "$LOG_SLICE_FILE" ]]; then
    log_probe_file="$LOG_SLICE_FILE"
  elif [[ -n "$ACTIVE_LOG" && -f "$ACTIVE_LOG" ]]; then
    log_probe_file="$ACTIVE_LOG"
  else
    return 0
  fi

  python3 - "$log_probe_file" <<'PY'
from pathlib import Path
import sys

log_path = Path(sys.argv[1])
marker = "Preview rebuilt ("
bootstrap_count = 0
unexpected_reasons = []

def is_geometry_affecting_preview_rebuild_reason(reason: str) -> bool:
    if reason == "project_bootstrap" or reason == "workspace_attribute":
        return True
    if reason.startswith("queued:"):
        return is_geometry_affecting_preview_rebuild_reason(reason.split(":", 1)[1])
    if reason.startswith("auto_retry_"):
        return True
    return (
        reason.startswith("source_changed:")
        or reason.startswith("descendant_added:")
        or reason.startswith("descendant_removed:")
    )

with log_path.open("r", encoding="utf-8", errors="replace") as handle:
    for raw_line in handle:
        if marker not in raw_line:
            continue
        tail = raw_line.split(marker, 1)[1]
        reason = tail.split(")", 1)[0].strip()
        if reason == "project_bootstrap":
            bootstrap_count += 1
            continue
        if not is_geometry_affecting_preview_rebuild_reason(reason):
            unexpected_reasons.append(reason)

if unexpected_reasons:
    print(
        "unexpected preview rebuild reasons: "
        + ", ".join(unexpected_reasons),
        file=sys.stderr,
    )
    raise SystemExit(1)

if bootstrap_count > 1:
    print(
        f"unexpected preview rebuild count for project_bootstrap: {bootstrap_count}",
        file=sys.stderr,
    )
    raise SystemExit(1)
PY
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

  local preflight_session_status="unknown"
  local preflight_log_indicates_play="false"

  preflight_session_status="$(studio_session_status_value status 2>/dev/null || printf 'unknown')"
  if studio_log_indicates_play_session; then
    preflight_log_indicates_play="true"
  fi

  MCP_PHASE="$phase" \
  MCP_BINARY_PATH="$MCP_BINARY" \
  MCP_PREFLIGHT_SESSION_STATUS="$preflight_session_status" \
  MCP_LOG_INDICATES_PLAY="$preflight_log_indicates_play" \
  python3 - <<'PY'
import json
import os
import signal
import sys

sys.path.insert(0, '/Users/adpena/Projects/vertigo/scripts/dev')
from studio_mcp_direct_lib import JsonRpcStdioClient, best_mode_from_payload
sys.path.insert(0, '/Users/adpena/Projects/arnis-roblox/scripts')
from studio_harness_policy import mcp_mode_stop_decision

phase = os.environ["MCP_PHASE"]
bin_path = os.environ["MCP_BINARY_PATH"]
scene_marker_luau = os.environ["SCENE_MARKER_LUAU"]
preflight_session_status = os.environ.get("MCP_PREFLIGHT_SESSION_STATUS", "unknown")
log_indicates_play = os.environ.get("MCP_LOG_INDICATES_PLAY", "false").strip().lower() in {"1", "true", "yes", "on"}
scene_marker_luau = os.environ["SCENE_MARKER_LUAU"]
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
    current_mode = best_mode_from_payload(mode_result)

    if current_mode == "stop":
        decision = mcp_mode_stop_decision(
            mode_label=current_mode,
            session_status=preflight_session_status,
            log_indicates_play=log_indicates_play,
        )
        if phase == "edit" and decision == "ignore":
            print(
                "[harness-mcp] phase=edit notice=ignoring-stop "
                + json.dumps(
                    {
                        "session_status": preflight_session_status,
                        "log_indicates_play": log_indicates_play,
                    },
                    separators=(",", ":"),
                )
            )
            current_mode = "edit"
        else:
            print(f"[harness-mcp] phase={phase} skip=studio-stop")
            raise SystemExit(0)

    if phase == "edit":
        result = client.call_tool(
            "run_code",
            {
                "command": (
                    """
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")
local SceneAudit = require(ServerScriptService.ImportService.SceneAudit)
"""
                    + scene_marker_luau
                    + """
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
emitSceneMarkers("ARNIS_SCENE_EDIT", "edit", "GeneratedWorld_AustinPreview", 1024, SceneAudit.summarizeWorld(root))
""").strip()
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

run_edit_actions_via_mcp() {
  if [[ -z "$MCP_BINARY" || ! -x "$MCP_BINARY" || $MCP_READY -ne 1 ]]; then
    return 1
  fi

  local edit_readiness_target="preview"
  if [[ -n "$RUNALL_SPEC_FILTER" && "$RUNALL_SPEC_FILTER" != *Preview* ]]; then
    edit_readiness_target="edit_sync"
  fi
  local edit_readiness_json=""
  local readiness_attempt=1
  local readiness_max_attempts=2
  while [[ $readiness_attempt -le $readiness_max_attempts ]]; do
    if edit_readiness_json="$(VSYNC_EDIT_READINESS_TARGET="$edit_readiness_target" wait_for_vsync_edit_readiness)"; then
      break
    fi

    if [[ $readiness_attempt -ge $readiness_max_attempts ]]; then
      log "edit-mode setup did not reach Vertigo Sync readiness before timeout"
      return 1
    fi

    log "edit-mode setup did not reach Vertigo Sync readiness before timeout; attempting Vertigo Sync recovery"
    recover_vsync_server_for_edit_readiness || {
      log "edit-mode readiness recovery failed"
      return 1
    }
    wait_for_mcp_ready || {
      log "Studio MCP helper did not become ready after Vertigo Sync recovery; retrying readiness anyway"
    }
    readiness_attempt=$((readiness_attempt + 1))
  done

  local mcp_wall_timeout=$((EDIT_WAIT_SECONDS + 150))
  if [[ $mcp_wall_timeout -lt 120 ]]; then
    mcp_wall_timeout=120
  fi
  if [[ $mcp_wall_timeout -gt 240 ]]; then
    mcp_wall_timeout=240
  fi

  local attempt=1
  local max_attempts=2
  while [[ $attempt -le $max_attempts ]]; do
    local preflight_status
    preflight_status="$(studio_session_status_value status)"
    if [[ "$preflight_status" == "blocked_dialog" ]]; then
      dismiss_startup_dialogs
      wait_for_session_status "ready_edit,ready_play,start_page,transitioning" 10 || true
    elif [[ "$preflight_status" == "transitioning" ]]; then
      wait_for_session_status "ready_edit,ready_play,start_page,blocked_dialog" 15 || true
    fi

    preflight_status="$(studio_session_status_value status)"
    if [[ "$preflight_status" != "ready_edit" ]]; then
      wait_for_editor_ready 20 >/dev/null 2>&1 || true
    fi

    local preflight_status_for_mcp="$preflight_status"
    local log_indicates_play_for_mcp="false"
    local host_probe_json="{}"
    if studio_log_indicates_play_session; then
      log_indicates_play_for_mcp="true"
    fi
    host_probe_json="$(sample_harness_host_probe_json)"

    (
    MCP_BINARY_PATH="$MCP_BINARY" \
    EDIT_WAIT_SECONDS="$EDIT_WAIT_SECONDS" \
    MCP_WALL_TIMEOUT="$mcp_wall_timeout" \
    MCP_PREFLIGHT_SESSION_STATUS="$preflight_status_for_mcp" \
    MCP_LOG_INDICATES_PLAY="$log_indicates_play_for_mcp" \
    HARNESS_HOST_PROBE_JSON="$host_probe_json" \
    VSYNC_READINESS_JSON="$edit_readiness_json" \
    RUNALL_EDIT_ENABLED="$RUNALL_EDIT_ENABLED" \
    RUNALL_SPEC_FILTER="$RUNALL_SPEC_FILTER" \
    python3 - <<'PY'
import json
import os
import signal
import sys
from pathlib import Path

sys.path.insert(0, '/Users/adpena/Projects/vertigo/scripts/dev')
from studio_mcp_direct_lib import JsonRpcStdioClient

root = Path('/Users/adpena/Projects/arnis-roblox')
sys.path.insert(0, str(root / 'scripts'))
from studio_harness_policy import build_readiness_expectation, mcp_mode_stop_decision

edit_wait_seconds = max(5, int(os.environ.get("EDIT_WAIT_SECONDS", "20")))
wall_clock_timeout = max(int(os.environ.get("MCP_WALL_TIMEOUT", "120")), edit_wait_seconds + 90, 120)
preflight_session_status = os.environ.get("MCP_PREFLIGHT_SESSION_STATUS", "unknown")
log_indicates_play = os.environ.get("MCP_LOG_INDICATES_PLAY", "false").strip().lower() in {"1", "true", "yes", "on"}
scene_marker_luau = os.environ["SCENE_MARKER_LUAU"]
readiness_record = json.loads(os.environ["VSYNC_READINESS_JSON"])
readiness = build_readiness_expectation(readiness_record)
run_edit_tests = os.environ.get("RUNALL_EDIT_ENABLED", "0").strip().lower() not in {"0", "false", "no", "off"}
runall_spec_filter = os.environ.get("RUNALL_SPEC_FILTER", "").strip()
run_preview_probe = runall_spec_filter == "" or "Preview" in runall_spec_filter
host_probe_sample = json.loads(os.environ.get("HARNESS_HOST_PROBE_JSON", "{}"))

def on_alarm(_signum, _frame):
    raise TimeoutError(f"run_edit_actions_via_mcp timed out after {wall_clock_timeout}s")

signal.signal(signal.SIGALRM, on_alarm)
signal.alarm(wall_clock_timeout)

client = JsonRpcStdioClient(
    os.environ["MCP_BINARY_PATH"],
    timeout_seconds=max(edit_wait_seconds + 90, 120),
    protocol_version='2025-11-25',
    client_name='arnis-studio-harness-edit',
)


def extract_mode_label(mode_result):
    if not isinstance(mode_result, dict):
        return ""
    for item in mode_result.get("content", []):
        if item.get("type") != "text":
            continue
        text = str(item.get("text", "")).strip().lower()
        if text:
            return text
    return ""

luau = (
    """
local HttpService = game:GetService("HttpService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local SceneAudit = require(ServerScriptService.ImportService.SceneAudit)
"""
    + scene_marker_luau
    + """
local payload = {
    runAll = nil,
    preview = nil,
    errors = {},
    hostProbe = nil,
}
local runEditTests = """ + ("true" if run_edit_tests else "false") + """
local runAllSpecFilter = """ + json.dumps(runall_spec_filter) + """
local runPreviewProbe = """ + ("true" if run_preview_probe else "false") + """
local hostProbeSample = """ + json.dumps(host_probe_sample, separators=(",", ":")) + """

Workspace:SetAttribute("ArnisStreamingHostProbeAvailableBytes", hostProbeSample.availableBytes)
Workspace:SetAttribute("ArnisStreamingHostProbePressureLevel", hostProbeSample.pressureLevel)
payload.hostProbe = hostProbeSample

local function waitForPreviewSyncCompletion(timeoutSeconds)
    local deadline = os.clock() + timeoutSeconds
    while os.clock() < deadline do
        local root = Workspace:FindFirstChild("GeneratedWorld_AustinPreview")
        local syncActive = Workspace:GetAttribute("VertigoPreviewSyncActive")
        local syncState = Workspace:GetAttribute("VertigoPreviewSyncState")
        if root and syncActive == false and syncState == "idle" then
            return root, nil
        end
        task.wait(0.25)
    end

    return Workspace:FindFirstChild("GeneratedWorld_AustinPreview"), string.format(
        "timeout waiting for preview sync completion (active=%s state=%s)",
        tostring(Workspace:GetAttribute("VertigoPreviewSyncActive")),
        tostring(Workspace:GetAttribute("VertigoPreviewSyncState"))
    )
end

if runEditTests then
    local testsFolder = ServerScriptService:FindFirstChild("Tests")
    if testsFolder then
        local runAllModule = testsFolder:FindFirstChild("RunAll")
        if runAllModule then
            local ok, runAllResult = pcall(function()
                return require(runAllModule).run({
                    specNameFilter = runAllSpecFilter,
                })
            end)
            if ok then
                payload.runAll = runAllResult
            else
                table.insert(payload.errors, "RunAll: " .. tostring(runAllResult))
            end
        else
            table.insert(payload.errors, "RunAll module missing")
        end
    else
        table.insert(payload.errors, "Tests folder missing")
    end
end

if runPreviewProbe then
    local previewFolder = ServerScriptService:FindFirstChild("StudioPreview")
    if previewFolder then
        local previewBuilderModule = previewFolder:FindFirstChild("AustinPreviewBuilder")
        if previewBuilderModule then
            local ok, previewResult = pcall(function()
                return require(previewBuilderModule).Build()
            end)
            if ok then
                local root, waitError = waitForPreviewSyncCompletion(90)
                local scene = SceneAudit.summarizeWorld(root)
                payload.preview = {
                    status = if waitError then "timeout" else "ok",
                    resultType = typeof(previewResult),
                    rootExists = root ~= nil,
                    children = root and #root:GetChildren() or 0,
                    sceneSummary = {
                        buildingModelCount = scene and scene.buildingModelCount or 0,
                        buildingModelsWithDirectRoof = scene and scene.buildingModelsWithDirectRoof or 0,
                        buildingModelsWithRoofClosureDeck = scene and scene.buildingModelsWithRoofClosureDeck or 0,
                        roadSurfacePartCount = scene and scene.roadSurfacePartCount or 0,
                        waterSurfacePartCount = scene and scene.waterSurfacePartCount or 0,
                        propInstanceCount = scene and scene.propInstanceCount or 0,
                    },
                }
                if waitError then
                    payload.preview.waitError = waitError
                    table.insert(payload.errors, "AustinPreviewBuilderWait: " .. waitError)
                end
                emitSceneMarkers("ARNIS_SCENE_EDIT", "edit", "GeneratedWorld_AustinPreview", 1024, scene)
            else
                table.insert(payload.errors, "AustinPreviewBuilder: " .. tostring(previewResult))
            end
        else
            table.insert(payload.errors, "AustinPreviewBuilder module missing")
        end
    else
        table.insert(payload.errors, "StudioPreview folder missing")
    end
else
    payload.preview = {
        status = "skipped",
        skipReason = "spec_filter_non_preview",
    }
end

print("ARNIS_MCP_EDIT_ACTION " .. HttpService:JSONEncode(payload))
""").strip()

try:
    client.initialize()
    mode_result = client.call_tool("get_studio_mode", {})
    print(f"[harness-mcp] phase=edit mode={json.dumps(mode_result, separators=(',', ':'))}")
    print(f"[harness-mcp] phase=edit readiness={json.dumps(readiness, separators=(',', ':'))}")
    mode_label = extract_mode_label(mode_result)
    if mode_label == "stop":
        decision = mcp_mode_stop_decision(
            mode_label=mode_label,
            session_status=preflight_session_status,
            log_indicates_play=log_indicates_play,
        )
        if decision == "ignore":
            print(
                "[harness-mcp] phase=edit notice=ignoring-stop "
                + json.dumps(
                    {
                        "session_status": preflight_session_status,
                        "log_indicates_play": log_indicates_play,
                    },
                    separators=(",", ":"),
                )
            )
            mode_label = "edit"
        else:
            print("[harness-mcp] phase=edit notice=studio-already-in-play")
            sys.exit(4)
    if mode_label and mode_label not in {"edit"}:
        print(f"[harness-mcp] phase=edit notice=studio-not-edit-ready mode={mode_label}")
        sys.exit(3)
    result = client.call_tool(
        "run_code",
        {"command": luau, "readiness": readiness},
        allow_is_error=True,
        timeout_seconds=max(edit_wait_seconds + 90, 120),
    )
    print(f"[harness-mcp] phase=edit action={json.dumps(result, separators=(',', ':'))}")
    action_text = ""
    for item in result.get("content", []):
        if item.get("type") == "text":
            action_text += item.get("text", "")
            action_text += "\n"

    for line in action_text.splitlines():
        marker = "ARNIS_MCP_EDIT_ACTION "
        if marker not in line:
            continue
        payload_text = line.split(marker, 1)[1].strip()
        payload = json.loads(payload_text)
        errors = payload.get("errors") or []
        if errors:
            raise RuntimeError("edit-mode harness errors: " + " | ".join(str(error) for error in errors))
        break
finally:
    signal.alarm(0)
    client.close()
PY
    ) &
    local probe_pid=$!
    local waited=0

    while kill -0 "$probe_pid" >/dev/null 2>&1; do
      if [[ $waited -ge $mcp_wall_timeout ]]; then
        log "edit-mode MCP actions exceeded ${mcp_wall_timeout}s; falling back to passive edit wait"
        kill -TERM "$probe_pid" >/dev/null 2>&1 || true
        sleep 1
        kill -KILL "$probe_pid" >/dev/null 2>&1 || true
        wait "$probe_pid" >/dev/null 2>&1 || true
        return 1
      fi
      sleep 1
      waited=$((waited + 1))
    done

    local exit_code=0
    if wait "$probe_pid"; then
      return 0
    fi
    exit_code=$?

    if [[ $exit_code -eq 4 && $attempt -lt $max_attempts ]]; then
      local current_session_status="unknown"
      current_session_status="$(studio_session_status_value status 2>/dev/null || printf 'unknown')"
      local log_indicates_play_now="false"
      if studio_log_indicates_play_session; then
        log_indicates_play_now="true"
      fi
      local ignore_mcp_stop_decision=""
      ignore_mcp_stop_decision="$(python3 "$STUDIO_HARNESS_POLICY" should-ignore-mcp-stop \
        --mode-label "stop" \
        --session-status "$current_session_status" \
        --log-indicates-play "$log_indicates_play_now" 2>/dev/null || true)"
      local should_ignore_mcp_stop="false"
      if [[ -n "$ignore_mcp_stop_decision" ]]; then
        should_ignore_mcp_stop="$(python3 -c 'import json,sys; print(str(bool(json.loads(sys.stdin.read()).get("should_ignore"))).lower())' <<<"$ignore_mcp_stop_decision" 2>/dev/null || printf 'false')"
      fi
      if [[ "$should_ignore_mcp_stop" == "true" ]]; then
        log "ignoring MCP stop because UI/log still indicate edit readiness; retrying edit actions"
        wait_for_editor_ready 20 >/dev/null 2>&1 || true
        attempt=$((attempt + 1))
        continue
      fi
      if studio_log_indicates_play_session; then
        log "edit-mode MCP found Studio already in play; stopping play and retrying edit actions"
        stop_play_mode || true
        wait_for_session_status "ready_edit,start_page,blocked_dialog,transitioning" 20 || true
        dismiss_startup_dialogs
      else
        log "edit-mode MCP reported stop without play markers; waiting for editor stabilization and retrying"
        wait_for_editor_ready 20 >/dev/null 2>&1 || true
      fi
      attempt=$((attempt + 1))
      continue
    fi

    if edit_action_completed_successfully_in_log; then
      log "edit-mode MCP transport failed after log-backed completion; accepting current edit result"
      return 0
    fi

    if [[ $exit_code -eq 3 || $exit_code -eq 4 ]]; then
      return 1
    fi
    return 2
  done

  return 1
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

  local mcp_wall_timeout=$((PLAY_WAIT_SECONDS + 25))
  if [[ $mcp_wall_timeout -lt 35 ]]; then
    mcp_wall_timeout=35
  fi
  if [[ $mcp_wall_timeout -gt 75 ]]; then
    mcp_wall_timeout=75
  fi

  (
    MCP_BINARY_PATH="$MCP_BINARY" MCP_PLAY_WAIT="$PLAY_WAIT_SECONDS" python3 - <<'PY'
import json
import os
import signal
import sys

sys.path.insert(0, '/Users/adpena/Projects/vertigo/scripts/dev')
from studio_mcp_direct_lib import JsonRpcStdioClient

wait_seconds = max(5, int(os.environ.get("MCP_PLAY_WAIT", "25")))
scene_marker_luau = os.environ["SCENE_MARKER_LUAU"]
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

luau = (
    """
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")
local SceneAudit = require(ServerScriptService.ImportService.SceneAudit)
"""
    + scene_marker_luau
    + """
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
    payload.austinBootstrapState = Workspace:GetAttribute("ArnisAustinBootstrapState")
    payload.austinBootstrapStateOrder = Workspace:GetAttribute("ArnisAustinBootstrapStateOrder")
    payload.austinBootstrapFailure = Workspace:GetAttribute("ArnisAustinBootstrapFailure")
    payload.austinBootstrapEntryCount = Workspace:GetAttribute("ArnisAustinBootstrapEntryCount")
    payload.austinBootstrapDuplicateCount = Workspace:GetAttribute("ArnisAustinBootstrapDuplicateCount")
    return payload
end

local deadline = os.clock() + __WAIT_SECONDS__
while os.clock() < deadline do
    local bootstrapState = Workspace:GetAttribute("ArnisAustinBootstrapState")
    if bootstrapState == "gameplay_ready" or bootstrapState == "failed" then
        break
    end
    task.wait(0.25)
end
local firstSample = sample()
print("ARNIS_MCP_PLAY " .. HttpService:JSONEncode(firstSample))
emitSceneMarkers("ARNIS_SCENE_PLAY", "play", "GeneratedWorld_Austin", 1500, SceneAudit.summarizeWorld(Workspace:FindFirstChild("GeneratedWorld_Austin")))
task.wait(2)
local lateSample = sample()
print("ARNIS_MCP_PLAY_LATE " .. HttpService:JSONEncode(lateSample))
emitSceneMarkers("ARNIS_SCENE_PLAY", "play", "GeneratedWorld_Austin", 1500, SceneAudit.summarizeWorld(Workspace:FindFirstChild("GeneratedWorld_Austin")))
""").strip()
luau = luau.replace("__WAIT_SECONDS__", str(wait_seconds))

try:
    client.initialize()
    try:
        client.call_tool("start_stop_play", {"mode": "stop"}, allow_is_error=True)
    except Exception:
        pass
    result = client.call_tool(
        "run_script_in_play_mode",
        {"mode": "start_play", "code": luau, "timeout": max(wait_seconds + 30, 60)},
        allow_is_error=True,
        timeout_seconds=max(wait_seconds + 35, 70),
    )
    print(f"[harness-mcp] phase=play run_script={json.dumps(result, separators=(',', ':'))}")
    text_fragments = []
    if isinstance(result, dict):
        if result.get("isError"):
            text_fragments.append("tool isError=true")
        for item in result.get("content", []):
            if isinstance(item, dict):
                text = item.get("text")
                if isinstance(text, str):
                    text_fragments.append(text)
    joined = "\n".join(text_fragments)
    if "Failed to run script in play mode" in joined or "Previous call to start play session has not been completed" in joined:
        raise RuntimeError(joined)
finally:
    signal.alarm(0)
    try:
        client.call_tool("start_stop_play", {"mode": "stop"}, allow_is_error=True)
    except Exception:
        pass
    client.close()
PY
  ) &
  local probe_pid=$!
  local waited=0

  while kill -0 "$probe_pid" >/dev/null 2>&1; do
    if [[ $waited -ge $mcp_wall_timeout ]]; then
      log "play-mode MCP probe exceeded ${mcp_wall_timeout}s; falling back to direct play control"
      kill -TERM "$probe_pid" >/dev/null 2>&1 || true
      sleep 1
      kill -KILL "$probe_pid" >/dev/null 2>&1 || true
      wait "$probe_pid" >/dev/null 2>&1 || true
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done

  wait "$probe_pid"
}

summarize_log() {
  local summary_source="$ACTIVE_LOG"
  if [[ -n "$LOG_SLICE_FILE" && -f "$LOG_SLICE_FILE" ]]; then
    summary_source="$LOG_SLICE_FILE"
  fi
  log "summary from $(basename "$ACTIVE_LOG")"
  grep -E "TestEZ tests complete|PASS |FAIL |Tests failed|BootstrapAustin|RunAustin|AustinPreviewBuilder|ArnisRoblox|VertigoSync|RunAll|Austin anchor|anchor resolved|ARNIS_MCP_PLAY|ARNIS_MCP_PLAY_LATE|ARNIS_MCP_EDIT|ARNIS_SCENE_EDIT|ARNIS_SCENE_PLAY|\\[harness-mcp\\]" "$summary_source" | tail -n 260 || true
}

run_scene_fidelity_audits() {
  local manifest_path="$ROOT_DIR/rust/out/austin-manifest.json"
  local manifest_sqlite_path="$ROOT_DIR/rust/out/austin-manifest.sqlite"
  local manifest_summary_path="$ROOT_DIR/rust/out/austin-manifest.scene-index.json"
  local audit_script="$ROOT_DIR/scripts/scene_fidelity_audit.py"
  local audit_log="$ACTIVE_LOG"
  local scene_audit_dir="${ARNIS_SCENE_AUDIT_DIR:-/tmp}"
  local manifest_scene_index_args=()
  if [[ ! -f "$audit_script" ]]; then
    log "scene fidelity audit unavailable; missing manifest or script"
    return 0
  fi
  if [[ -f "$manifest_sqlite_path" ]]; then
    manifest_scene_index_args=(--manifest-sqlite "$manifest_sqlite_path")
  elif [[ -f "$manifest_path" ]]; then
    manifest_scene_index_args=(--manifest "$manifest_path")
  else
    log "scene fidelity audit unavailable; missing manifest or script"
    return 0
  fi
  if [[ -n "$LOG_SLICE_FILE" && -f "$LOG_SLICE_FILE" ]]; then
    audit_log="$LOG_SLICE_FILE"
  fi
  mkdir -p "$scene_audit_dir"

  local edit_json="$scene_audit_dir/arnis-scene-fidelity-edit.json"
  local edit_html="$scene_audit_dir/arnis-scene-fidelity-edit.html"
  local play_json="$scene_audit_dir/arnis-scene-fidelity-play.json"
  local play_html="$scene_audit_dir/arnis-scene-fidelity-play.html"

  local refresh_manifest_summary=0
  if [[ ! -f "$manifest_summary_path" ]]; then
    refresh_manifest_summary=1
  elif [[ -f "$manifest_sqlite_path" && "$manifest_sqlite_path" -nt "$manifest_summary_path" ]]; then
    refresh_manifest_summary=1
  elif [[ -f "$manifest_path" && "$manifest_path" -nt "$manifest_summary_path" ]]; then
    refresh_manifest_summary=1
  elif find \
    "$ROOT_DIR/rust/crates/arbx_cli/src" \
    "$ROOT_DIR/rust/crates/arbx_cli/Cargo.toml" \
    "$ROOT_DIR/rust/Cargo.lock" \
    -type f -newer "$manifest_summary_path" -print -quit 2>/dev/null | grep -q .; then
    refresh_manifest_summary=1
  elif ! python3 - "$manifest_summary_path" "$SCENE_INDEX_VERSION" <<'PY'
from pathlib import Path
import json
import sys

summary_path = Path(sys.argv[1])
expected_version = int(sys.argv[2])

try:
    data = json.loads(summary_path.read_text())
except Exception:
    raise SystemExit(1)

meta = data.get("meta") or {}
chunks = data.get("chunks")
if meta.get("sceneIndexVersion") != expected_version:
    raise SystemExit(1)
if not isinstance(chunks, list):
    raise SystemExit(1)
if chunks:
    required_keys = {
        "roadsWithSidewalks",
        "roadsWithCrossings",
        "chunksWithSidewalkRoads",
        "chunksWithCrossingRoads",
    }
    if not required_keys.issubset(chunks[0].keys()):
        raise SystemExit(1)
PY
  then
    refresh_manifest_summary=1
  fi

  if [[ $refresh_manifest_summary -eq 1 ]]; then
    log "refreshing manifest scene index"
    cargo run --quiet --manifest-path "$ROOT_DIR/rust/Cargo.toml" -p arbx_cli -- scene-index \
      "${manifest_scene_index_args[@]}" \
      --json-out "$manifest_summary_path"
  fi

  if rg -q "^ARNIS_SCENE_EDIT " "$audit_log"; then
    log "writing scene fidelity edit artifact"
    cargo run --quiet --manifest-path "$ROOT_DIR/rust/Cargo.toml" -p arbx_cli -- scene-audit \
      --manifest-summary "$manifest_summary_path" \
      --log "$audit_log" \
      --marker ARNIS_SCENE_EDIT \
      --json-out "$edit_json"
    python3 "$audit_script" \
      --report-json "$edit_json" \
      --html-out "$edit_html"
  fi

  if rg -q "^ARNIS_SCENE_PLAY " "$audit_log"; then
    log "writing scene fidelity play artifact"
    cargo run --quiet --manifest-path "$ROOT_DIR/rust/Cargo.toml" -p arbx_cli -- scene-audit \
      --manifest-summary "$manifest_summary_path" \
      --log "$audit_log" \
      --marker ARNIS_SCENE_PLAY \
      --json-out "$play_json"
    python3 "$audit_script" \
      --report-json "$play_json" \
      --html-out "$play_html"
  fi
}

run_plugin_smoke_check() {
  if [[ $SKIP_PLUGIN_SMOKE -eq 1 ]]; then
    log "skipping Vertigo Sync plugin smoke check"
    return 0
  fi

  if ! ensure_vsync_binary_fresh; then
    log "vsync binary unavailable; skipping plugin smoke check"
    return 0
  fi

  local summary_source="$ACTIVE_LOG"
  if [[ -n "$LOG_SLICE_FILE" && -f "$LOG_SLICE_FILE" ]]; then
    summary_source="$LOG_SLICE_FILE"
  fi

  log "running Vertigo Sync plugin smoke check"
  "$VSYNC_BINARY" plugin-smoke-log \
    --log "$summary_source" \
    --ignore-cloud-plugins \
    --allow-plugin user_VertigoSyncPlugin.lua \
    --allow-plugin user_MCPStudioPlugin.rbxm
}

enable_runall_entry
ensure_vsync_plugin_installed
auto_prepare_place
ensure_vsync_server_running
start_memory_monitor

prepare_log_cursor
quarantine_foreign_plugins
purge_harness_autosaves

CURRENT_STUDIO_STATUS="$(studio_session_status_value status)"
if [[ "$CURRENT_STUDIO_STATUS" != "not_running" ]]; then
  if [[ $ALLOW_TAKEOVER -eq 0 ]]; then
    echo "[harness] Roblox Studio is already running (status=$CURRENT_STUDIO_STATUS); refusing to take over it without --takeover" >&2
    exit 1
  fi

  if [[ $DO_RESTART -eq 1 || $HARD_RESTART -eq 1 ]]; then
    if [[ $HARD_RESTART -eq 1 ]]; then
      log "hard restarting Roblox Studio"
    else
      log "taking over Roblox Studio with a clean relaunch"
    fi
    if [[ $HARD_RESTART -eq 1 ]]; then
      if ! force_quit_studio; then
        echo "[harness] failed to fully force-quit Roblox Studio before hard restart" >&2
        exit 1
      fi
    else
      quit_studio
    fi
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
    wait_for_editor_ready "$PATTERN_WAIT_SECONDS" || {
      log "Studio editor did not become ready after relaunch before timeout; continuing with best effort"
    }
    if wait_for_mcp_ready; then
      MCP_READY=1
    else
      MCP_READY=0
      log "Studio MCP helper did not become ready after relaunch; edit-mode MCP actions will stay disabled"
    fi
  else
    log "reusing existing Roblox Studio session without restart (status=$CURRENT_STUDIO_STATUS)"
    ATTACHED_TO_EXISTING_STUDIO=1
    CLOSE_ON_EXIT=0
    RELAUNCH_FOR_PLAY=0
    ACTIVE_LOG="$(latest_studio_log)"
    if [[ -z "$ACTIVE_LOG" ]]; then
      echo "[harness] failed to locate an existing Studio log file while attaching" >&2
      exit 1
    fi
    switch_to_log "$ACTIVE_LOG"
    if [[ "$CURRENT_STUDIO_STATUS" == "blocked_dialog" ]]; then
      log "attached Studio session is blocked by a dialog; attempting dismissal"
      dismiss_startup_dialogs
      wait_for_session_status "ready_edit,ready_play,start_page,transitioning" 10 || true
      CURRENT_STUDIO_STATUS="$(studio_session_status_value status)"
    fi
    if [[ "$CURRENT_STUDIO_STATUS" == "transitioning" ]]; then
      log "attached Studio session is still transitioning; waiting for a stable state"
      wait_for_session_status "ready_edit,ready_play,start_page,blocked_dialog" "$PATTERN_WAIT_SECONDS" || true
      CURRENT_STUDIO_STATUS="$(studio_session_status_value status)"
    fi
    if [[ "$CURRENT_STUDIO_STATUS" == "ready_edit" ]]; then
      wait_for_editor_ready "$PATTERN_WAIT_SECONDS" || {
        log "attached Studio session did not become editor-ready before timeout; continuing with best effort"
      }
      if wait_for_mcp_ready; then
        MCP_READY=1
      else
        MCP_READY=0
        log "Studio MCP helper did not become ready while attaching to edit mode; edit-mode MCP actions will stay disabled"
      fi
    fi
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
  wait_for_editor_ready "$PATTERN_WAIT_SECONDS" || {
    log "Studio editor did not become ready after initial launch before timeout; continuing with best effort"
  }
  if wait_for_mcp_ready; then
    MCP_READY=1
  else
    MCP_READY=0
    log "Studio MCP helper did not become ready after initial launch; edit-mode MCP actions will stay disabled"
  fi
fi

if [[ -n "$MCP_BINARY" ]]; then
  log "detected Studio MCP helper: $MCP_BINARY"
else
  log "Studio MCP helper not found in PATH (rbx-studio-mcp); localhost plugin integration may be unavailable"
fi

CURRENT_STUDIO_STATUS="$(studio_session_status_value status)"
ATTACHED_SESSION_ALREADY_PLAYING=0
if [[ $ATTACHED_TO_EXISTING_STUDIO -eq 1 ]] && attached_session_is_really_playing; then
  ATTACHED_SESSION_ALREADY_PLAYING=1
  log "attached Studio session is already in play; skipping edit-mode setup"
  DO_PLAY=0
elif [[ $ATTACHED_TO_EXISTING_STUDIO -eq 1 && "$CURRENT_STUDIO_STATUS" == "ready_play" ]]; then
  log "Studio reported play-ready on attach, but the current log has no play-session markers; continuing with edit-mode setup"
fi

if [[ $ATTACHED_TO_EXISTING_STUDIO -eq 0 || $ATTACHED_SESSION_ALREADY_PLAYING -eq 0 ]]; then
  edit_mcp_status=0
  edit_actions_via_mcp=0
  edit_actions_via_runall_entry=0
  if run_edit_actions_via_mcp; then
    edit_actions_via_mcp=1
    log "triggered edit-mode actions via MCP"
  else
    edit_mcp_status=$?
    if [[ $edit_mcp_status -eq 2 ]]; then
      echo "[harness] edit-mode MCP actions reported harness failures" >&2
      exit 1
    fi
    if run_edit_actions_via_runall_entry; then
      edit_actions_via_runall_entry=1
      log "triggered edit-mode actions via RunAllEntry fallback"
    else
      log "edit-mode MCP actions unavailable; falling back to passive edit wait"
    fi
  fi
  log "waiting for edit-mode harness output"
  if wait_for_edit_completion; then
    if [[ $edit_actions_via_mcp -eq 0 && $edit_actions_via_runall_entry -eq 0 ]]; then
      sleep "$EDIT_WAIT_SECONDS"
    fi
  else
    log "edit-mode harness result not observed before timeout; continuing with captured output"
  fi
  log "capturing edit screenshot"
  capture_studio_screenshot "edit"
  if ! validate_preview_rebuild_behavior; then
    echo "[harness] preview rebuild behavior regressed" >&2
    exit 1
  fi
  if [[ $edit_actions_via_mcp -eq 1 ]] && edit_action_completed_successfully_in_log; then
    log "skipping redundant edit MCP probe after successful log-backed edit action"
  else
    log "capturing edit MCP probe"
    run_probe_best_effort "edit" 5
  fi
fi

if [[ $ATTACHED_TO_EXISTING_STUDIO -eq 1 && $ATTACHED_SESSION_ALREADY_PLAYING -eq 1 ]]; then
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
    if wait_for_log_pattern "\\[BootstrapAustin\\] state=gameplay_ready|\\[BootstrapAustin\\] state=failed" "$PATTERN_WAIT_SECONDS"; then
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
capture_preview_telemetry_artifacts
run_scene_fidelity_audits
run_plugin_smoke_check

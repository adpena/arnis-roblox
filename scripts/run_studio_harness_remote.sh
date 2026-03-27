#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_ARNIS_DIR="$ROOT_DIR"
COMMON_GIT_DIR="$(git -C "$ROOT_DIR" rev-parse --git-common-dir)"
DEFAULT_VSYNC_DIR="$(cd "$(dirname "$COMMON_GIT_DIR")/.." && pwd)/vertigo-sync"
LOCAL_VSYNC_DIR="${VSYNC_REPO_DIR:-$DEFAULT_VSYNC_DIR}"
LOCAL_REMOTE_CONFIG="$ROOT_DIR/scripts/remote_studio_profiles.local.sh"
EXAMPLE_REMOTE_CONFIG="$ROOT_DIR/scripts/remote_studio_profiles.example.sh"

if [[ -f "$LOCAL_REMOTE_CONFIG" ]]; then
  # shellcheck disable=SC1090
  source "$LOCAL_REMOTE_CONFIG"
fi

REMOTE_PROFILE="${ARNIS_REMOTE_STUDIO_PROFILE:-primary}"
REMOTE_HOME_TOKEN="__REMOTE_HOME__"
DEFAULT_REMOTE_ROOT="$REMOTE_HOME_TOKEN/.codex-remote-studio"
DEFAULT_REMOTE_ARNIS_BASE="$REMOTE_HOME_TOKEN/Projects/arnis-roblox"
DEFAULT_REMOTE_VSYNC_BASE="$REMOTE_HOME_TOKEN/Projects/vertigo-sync"

resolve_profile_value() {
  local base_name="$1"
  local profile_name="$2"
  local fallback="$3"
  local profile_key
  profile_key="$(printf '%s' "$profile_name" | tr '[:lower:]-.' '[:upper:]__')"
  local scoped_name="${base_name}_${profile_key}"
  local resolved="${!base_name:-}"
  if [[ -z "$resolved" ]]; then
    resolved="${!scoped_name:-}"
  fi
  if [[ -z "$resolved" ]]; then
    resolved="$fallback"
  fi
  printf '%s' "$resolved"
}

render_rsync_remote_path() {
  case "$1" in
    __REMOTE_HOME__/*)
      printf '~/%s' "${1#__REMOTE_HOME__/}"
      ;;
    *)
      printf '%s' "$1"
      ;;
  esac
}

reset_remote_stage_dir() {
  local remote_dir="$1"
  ssh "$REMOTE_HOST" 'bash -s' -- "$remote_dir" <<'SH'
set -euo pipefail
expand_remote_path() {
  case "$1" in
    __REMOTE_HOME__/*)
      printf '%s\n' "$HOME/${1#__REMOTE_HOME__/}"
      ;;
    *)
      printf '%s\n' "$1"
      ;;
  esac
}

remote_dir="$(expand_remote_path "$1")"
rm -rf "$remote_dir"
mkdir -p "$remote_dir"
SH
}

sync_repo_snapshot() {
  local repo_dir="$1"
  local remote_dir="$2"
  local rsync_remote_dir="$3"
  local manifest
  manifest="$(mktemp)"
  git -C "$repo_dir" ls-files -z --cached --others --exclude-standard > "$manifest"
  reset_remote_stage_dir "$remote_dir"
  rsync -a --from0 --files-from="$manifest" "$repo_dir"/ "$REMOTE_HOST:$rsync_remote_dir/"
  rm -f "$manifest"
}

REMOTE_HOST="$(resolve_profile_value ARNIS_REMOTE_STUDIO_HOST "$REMOTE_PROFILE" "")"
REMOTE_ROOT="$(resolve_profile_value ARNIS_REMOTE_STUDIO_ROOT "$REMOTE_PROFILE" "$DEFAULT_REMOTE_ROOT")"
REMOTE_ARNIS_BASE="$(resolve_profile_value ARNIS_REMOTE_STUDIO_BASE_ARNIS "$REMOTE_PROFILE" "$DEFAULT_REMOTE_ARNIS_BASE")"
REMOTE_VSYNC_BASE="$(resolve_profile_value ARNIS_REMOTE_STUDIO_BASE_VSYNC "$REMOTE_PROFILE" "$DEFAULT_REMOTE_VSYNC_BASE")"
REMOTE_VSYNC_TARGET_DIR="$(resolve_profile_value ARNIS_REMOTE_STUDIO_VSYNC_TARGET_DIR "$REMOTE_PROFILE" "$REMOTE_VSYNC_BASE/target")"
LOCAL_ARTIFACT_DIR="${ARNIS_REMOTE_STUDIO_ARTIFACT_DIR:-/tmp/arnis-remote-studio}"
SYNC_STAGE=1

REMOTE_ARNIS_DIR="$REMOTE_ROOT/arnis-roblox"
REMOTE_VSYNC_DIR="$REMOTE_ROOT/vertigo-sync"
RSYNC_REMOTE_ARNIS_DIR="$(render_rsync_remote_path "$REMOTE_ARNIS_DIR")"
RSYNC_REMOTE_VSYNC_DIR="$(render_rsync_remote_path "$REMOTE_VSYNC_DIR")"

usage() {
  cat <<EOF
Usage: $(basename "$0") [remote-runner-options] -- [run_studio_harness options]

Runs the existing Studio harness on a remote macOS host after syncing this exact
arnis-roblox worktree and adjacent vertigo-sync snapshot to a persistent remote stage.

Remote runner options:
  --remote-profile PROFILE
                      Remote profile alias. Default: ${ARNIS_REMOTE_STUDIO_PROFILE:-primary}
  --remote-host HOST   Remote SSH host. Overrides profile/local config.
  --remote-root PATH   Persistent remote stage root. Overrides profile/local config.
  --no-sync            Reuse the existing remote stage without rsyncing local snapshots.
  --help               Show this help.

Local config:
  Create scripts/remote_studio_profiles.local.sh from the example template:
    $EXAMPLE_REMOTE_CONFIG

All remaining arguments are forwarded to scripts/run_studio_harness.sh on the remote host.
Example:
  $(basename "$0") --remote-profile primary -- --no-play --edit-tests --spec-filter ImportManifestRegistrationChunkTruth.spec
EOF
}

HARNESS_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --remote-profile)
      REMOTE_PROFILE="$2"
      shift 2
      ;;
    --remote-host)
      REMOTE_HOST="$2"
      shift 2
      ;;
    --remote-root)
      REMOTE_ROOT="$2"
      REMOTE_ARNIS_DIR="$REMOTE_ROOT/arnis-roblox"
      REMOTE_VSYNC_DIR="$REMOTE_ROOT/vertigo-sync"
      shift 2
      ;;
    --no-sync)
      SYNC_STAGE=0
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    --)
      shift
      HARNESS_ARGS+=("$@")
      break
      ;;
    *)
      HARNESS_ARGS+=("$1")
      shift
      ;;
  esac
done

REMOTE_HOST="${REMOTE_HOST:-$(resolve_profile_value ARNIS_REMOTE_STUDIO_HOST "$REMOTE_PROFILE" "")}"
REMOTE_ROOT="${REMOTE_ROOT:-$(resolve_profile_value ARNIS_REMOTE_STUDIO_ROOT "$REMOTE_PROFILE" "$DEFAULT_REMOTE_ROOT")}"
REMOTE_ARNIS_BASE="${REMOTE_ARNIS_BASE:-$(resolve_profile_value ARNIS_REMOTE_STUDIO_BASE_ARNIS "$REMOTE_PROFILE" "$DEFAULT_REMOTE_ARNIS_BASE")}"
REMOTE_VSYNC_BASE="${REMOTE_VSYNC_BASE:-$(resolve_profile_value ARNIS_REMOTE_STUDIO_BASE_VSYNC "$REMOTE_PROFILE" "$DEFAULT_REMOTE_VSYNC_BASE")}"
REMOTE_VSYNC_TARGET_DIR="${REMOTE_VSYNC_TARGET_DIR:-$(resolve_profile_value ARNIS_REMOTE_STUDIO_VSYNC_TARGET_DIR "$REMOTE_PROFILE" "$REMOTE_VSYNC_BASE/target")}"
REMOTE_ARNIS_DIR="$REMOTE_ROOT/arnis-roblox"
REMOTE_VSYNC_DIR="$REMOTE_ROOT/vertigo-sync"
RSYNC_REMOTE_ARNIS_DIR="$(render_rsync_remote_path "$REMOTE_ARNIS_DIR")"
RSYNC_REMOTE_VSYNC_DIR="$(render_rsync_remote_path "$REMOTE_VSYNC_DIR")"

if [[ -z "$REMOTE_HOST" ]]; then
  PROFILE_ENV_SUFFIX="$(printf '%s' "$REMOTE_PROFILE" | tr '[:lower:]-.' '[:upper:]__')"
  echo "[remote-harness] no remote host configured for profile '$REMOTE_PROFILE'" >&2
  echo "[remote-harness] set --remote-host, export ARNIS_REMOTE_STUDIO_HOST_${PROFILE_ENV_SUFFIX}, or create $LOCAL_REMOTE_CONFIG from $EXAMPLE_REMOTE_CONFIG" >&2
  exit 1
fi

if [[ ! -d "$LOCAL_ARNIS_DIR" ]]; then
  echo "[remote-harness] missing local arnis repo: $LOCAL_ARNIS_DIR" >&2
  exit 1
fi

if [[ ! -d "$LOCAL_VSYNC_DIR" ]]; then
  echo "[remote-harness] missing local vertigo-sync repo: $LOCAL_VSYNC_DIR" >&2
  exit 1
fi

mkdir -p "$LOCAL_ARTIFACT_DIR"

ssh "$REMOTE_HOST" 'bash -s' -- "$REMOTE_ROOT" "$REMOTE_ARNIS_BASE" "$REMOTE_VSYNC_BASE" <<'SH'
set -euo pipefail
expand_remote_path() {
  case "$1" in
    __REMOTE_HOME__/*)
      printf '%s\n' "$HOME/${1#__REMOTE_HOME__/}"
      ;;
    *)
      printf '%s\n' "$1"
      ;;
  esac
}

remote_root="$(expand_remote_path "$1")"
remote_arnis_base="$(expand_remote_path "$2")"
remote_vsync_base="$(expand_remote_path "$3")"
remote_arnis_dir="$remote_root/arnis-roblox"
remote_vsync_dir="$remote_root/vertigo-sync"

seed_stage() {
  local source_dir="$1"
  local dest_dir="$2"
  if [[ -d "$dest_dir" ]]; then
    return 0
  fi
  if [[ ! -d "$source_dir" ]]; then
    mkdir -p "$dest_dir"
    return 0
  fi
  mkdir -p "$dest_dir"
  if git -C "$source_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$source_dir" ls-files -z --cached --others --exclude-standard | \
      rsync -a --from0 --files-from=- "$source_dir"/ "$dest_dir"/
    return 0
  fi

  rsync -a --delete \
    --exclude=.git \
    --exclude=.worktrees \
    --exclude=target \
    --exclude=roblox/out \
    --exclude=.DS_Store \
    --exclude='**/__pycache__' \
    "$source_dir"/ "$dest_dir"/
}

mkdir -p "$remote_root"
seed_stage "$remote_arnis_base" "$remote_arnis_dir"
seed_stage "$remote_vsync_base" "$remote_vsync_dir"
SH

if [[ $SYNC_STAGE -eq 1 ]]; then
  sync_repo_snapshot "$LOCAL_ARNIS_DIR" "$REMOTE_ARNIS_DIR" "$RSYNC_REMOTE_ARNIS_DIR"
  sync_repo_snapshot "$LOCAL_VSYNC_DIR" "$REMOTE_VSYNC_DIR" "$RSYNC_REMOTE_VSYNC_DIR"
fi

ssh "$REMOTE_HOST" 'bash -s' -- "$SYNC_STAGE" "$REMOTE_ARNIS_DIR" "$REMOTE_VSYNC_DIR" "$REMOTE_VSYNC_TARGET_DIR" "${HARNESS_ARGS[@]}" <<'SH'
set -euo pipefail
expand_remote_path() {
  case "$1" in
    __REMOTE_HOME__/*)
      printf '%s\n' "$HOME/${1#__REMOTE_HOME__/}"
      ;;
    *)
      printf '%s\n' "$1"
      ;;
  esac
}

sync_stage="$1"
shift
remote_arnis_dir="$(expand_remote_path "$1")"
shift
remote_vsync_dir="$(expand_remote_path "$1")"
shift
remote_vsync_target_dir="$(expand_remote_path "$1")"
shift

ensure_remote_stage_ready() {
  local arnis_dir="$1"
  local vsync_dir="$2"
  local hint=""
  if [[ "$sync_stage" -eq 0 ]]; then
    hint="; re-run without --no-sync to seed the remote stage from the current worktree"
  fi
  if [[ ! -f "$arnis_dir/scripts/run_studio_harness.sh" ]]; then
    echo "[remote-harness] missing remote arnis stage at $arnis_dir$hint" >&2
    exit 1
  fi
  if [[ ! -f "$vsync_dir/Cargo.toml" ]]; then
    echo "[remote-harness] missing remote vertigo-sync stage at $vsync_dir$hint" >&2
    exit 1
  fi
}

needs_vsync_build() {
  local repo_dir="$1"
  local target_dir="$2"
  local binary="$target_dir/debug/vsync"
  if [[ ! -x "$binary" ]]; then
    return 0
  fi

  local source_path=""
  for source_path in \
    "$repo_dir/Cargo.toml" \
    "$repo_dir/Cargo.lock" \
    "$repo_dir/src" \
    "$repo_dir/assets"; do
    if [[ -e "$source_path" ]] && find "$source_path" -type f -newer "$binary" -print -quit | grep -q .; then
      return 0
    fi
  done

  return 1
}

ensure_remote_stage_ready "$remote_arnis_dir" "$remote_vsync_dir"

if needs_vsync_build "$remote_vsync_dir" "$remote_vsync_target_dir"; then
  CARGO_TARGET_DIR="$remote_vsync_target_dir" \
  cargo build --manifest-path "$remote_vsync_dir/Cargo.toml" --bin vsync >/dev/null
fi

cd "$remote_arnis_dir"
VSYNC_REPO_DIR="$remote_vsync_dir" \
VSYNC_BIN="$remote_vsync_target_dir/debug/vsync" \
bash scripts/run_studio_harness.sh "$@"
SH

remote_latest_log="$(ssh "$REMOTE_HOST" 'latest=$(ls -1t "$HOME"/Library/Logs/Roblox/*_Studio_*_last.log 2>/dev/null | head -n 1 || true); printf "%s" "$latest"')"
if [[ -n "$remote_latest_log" ]]; then
  rsync -a "$REMOTE_HOST:$remote_latest_log" "$LOCAL_ARTIFACT_DIR/"
fi

for remote_artifact in \
  /tmp/arnis-studio-harness-edit.png \
  /tmp/arnis-studio-harness-play.png \
  /tmp/arnis-preview-plugin-state.json \
  /tmp/arnis-preview-telemetry-summary.txt; do
  rsync -a "$REMOTE_HOST:$remote_artifact" "$LOCAL_ARTIFACT_DIR/" >/dev/null 2>&1 || true
done

echo "[remote-harness] remote host: $REMOTE_HOST"
echo "[remote-harness] remote profile: $REMOTE_PROFILE"
echo "[remote-harness] remote arnis dir: $REMOTE_ARNIS_DIR"
echo "[remote-harness] remote vsync dir: $REMOTE_VSYNC_DIR"
echo "[remote-harness] local artifacts: $LOCAL_ARTIFACT_DIR"

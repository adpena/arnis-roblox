#!/usr/bin/env bash
set -euo pipefail

TMUX_REMOTE_CONF="$HOME/.tmux.remote-dev.conf"
TMUX_MAIN_CONF="$HOME/.tmux.conf"
TMUX_SOURCE_LINE="if-shell '[ -f ~/.tmux.remote-dev.conf ]' 'source-file ~/.tmux.remote-dev.conf'"

if ! command -v brew >/dev/null 2>&1; then
  echo "[remote-dev-setup] Homebrew is required on this machine." >&2
  exit 1
fi

BREW_BIN="$(command -v brew)"

ensure_brew_package() {
  local package_name="$1"
  if "$BREW_BIN" list --formula "$package_name" >/dev/null 2>&1; then
    return 0
  fi
  "$BREW_BIN" install "$package_name"
}

ensure_brew_cask() {
  local cask_name="$1"
  if "$BREW_BIN" list --cask "$cask_name" >/dev/null 2>&1; then
    return 0
  fi
  "$BREW_BIN" install --cask "$cask_name"
}

ensure_tailscale() {
  if "$BREW_BIN" list --cask tailscale >/dev/null 2>&1; then
    return 0
  fi
  if "$BREW_BIN" install --cask tailscale; then
    return 0
  fi
  echo "[remote-dev-setup] tailscale cask install requires an interactive admin step on this machine" >&2
  return 0
}

ensure_tmux_remote_conf() {
  local tmp_conf
  tmp_conf="$(mktemp)"
  cat >"$tmp_conf" <<'EOF'
# Shared remote-development tmux overlay for Blink/Termius/mosh sessions.
set -g default-terminal "tmux-256color"
set -ag terminal-overrides ",xterm-256color:RGB"
set -g focus-events on
set -g allow-passthrough on
set -g set-clipboard on
set -s escape-time 0
EOF
  if [[ ! -f "$TMUX_REMOTE_CONF" ]] || ! cmp -s "$tmp_conf" "$TMUX_REMOTE_CONF"; then
    mv "$tmp_conf" "$TMUX_REMOTE_CONF"
  else
    rm -f "$tmp_conf"
  fi
}

ensure_tmux_main_sources_remote_conf() {
  touch "$TMUX_MAIN_CONF"
  if grep -Fqx "$TMUX_SOURCE_LINE" "$TMUX_MAIN_CONF"; then
    return 0
  fi
  printf '\n%s\n' "$TMUX_SOURCE_LINE" >>"$TMUX_MAIN_CONF"
}

report_tailscale_state() {
  if ! command -v tailscale >/dev/null 2>&1; then
    echo "[remote-dev-setup] tailscale CLI not found after install; complete the admin install step locally" >&2
    return 0
  fi
  if tailscale status >/dev/null 2>&1; then
    echo "[remote-dev-setup] tailscale: connected"
    return 0
  fi
  echo "[remote-dev-setup] tailscale: installed, sign-in or daemon start may still be required"
  return 0
}

mkdir -p "$HOME/Projects"

ensure_brew_package tmux
ensure_brew_package mosh
ensure_brew_package uv
ensure_tmux_remote_conf
ensure_tmux_main_sources_remote_conf
ensure_tailscale

echo "[remote-dev-setup] tmux overlay: $TMUX_REMOTE_CONF"
echo "[remote-dev-setup] tmux main config: $TMUX_MAIN_CONF"
report_tailscale_state

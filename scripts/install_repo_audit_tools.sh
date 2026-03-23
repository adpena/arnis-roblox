#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="${ROOT_DIR}/.tools/bin"
mkdir -p "$BIN_DIR"

OS="$(uname -s)"
ARCH="$(uname -m)"

download_gitleaks() {
  local version="8.30.0"
  local archive=""
  case "$OS-$ARCH" in
    Darwin-arm64) archive="gitleaks_${version#v}_darwin_arm64.tar.gz" ;;
    Darwin-x86_64) archive="gitleaks_${version#v}_darwin_x64.tar.gz" ;;
    Linux-x86_64) archive="gitleaks_${version#v}_linux_x64.tar.gz" ;;
    Linux-aarch64|Linux-arm64) archive="gitleaks_${version#v}_linux_arm64.tar.gz" ;;
    *)
      echo "[install_repo_audit_tools] unsupported platform for gitleaks: $OS-$ARCH" >&2
      return 1
      ;;
  esac

  local tmp_dir
  tmp_dir="$(mktemp -d)"
  curl -LsSf "https://github.com/gitleaks/gitleaks/releases/download/v${version}/${archive}" -o "$tmp_dir/gitleaks.tar.gz"
  tar -xzf "$tmp_dir/gitleaks.tar.gz" -C "$tmp_dir"
  mv "$tmp_dir/gitleaks" "$BIN_DIR/gitleaks"
  chmod +x "$BIN_DIR/gitleaks"
  rm -rf "$tmp_dir"
}

download_git_sizer() {
  local version="1.5.0"
  local archive=""
  case "$OS-$ARCH" in
    Darwin-arm64) archive="git-sizer-${version}-darwin-arm64.zip" ;;
    Darwin-x86_64) archive="git-sizer-${version}-darwin-amd64.zip" ;;
    Linux-x86_64) archive="git-sizer-${version}-linux-amd64.zip" ;;
    Linux-aarch64|Linux-arm64) archive="git-sizer-${version}-linux-arm64.zip" ;;
    *)
      echo "[install_repo_audit_tools] unsupported platform for git-sizer: $OS-$ARCH" >&2
      return 1
      ;;
  esac

  local tmp_dir
  tmp_dir="$(mktemp -d)"
  curl -LsSf "https://github.com/github/git-sizer/releases/download/v${version}/${archive}" -o "$tmp_dir/git-sizer.zip"
  unzip -q "$tmp_dir/git-sizer.zip" -d "$tmp_dir"
  mv "$tmp_dir/git-sizer" "$BIN_DIR/git-sizer"
  chmod +x "$BIN_DIR/git-sizer"
  rm -rf "$tmp_dir"
}

install_git_filter_repo() {
  if command -v git-filter-repo >/dev/null 2>&1; then
    return 0
  fi

  if command -v brew >/dev/null 2>&1; then
    brew install git-filter-repo
    return 0
  fi

  python3 -m pip install --user git-filter-repo
}

if ! command -v gitleaks >/dev/null 2>&1; then
  download_gitleaks
fi

if ! command -v git-sizer >/dev/null 2>&1; then
  download_git_sizer
fi

install_git_filter_repo

echo "[install_repo_audit_tools] installed tools in $BIN_DIR"
echo "[install_repo_audit_tools] add to PATH if needed: export PATH=\"$BIN_DIR:\$PATH\""

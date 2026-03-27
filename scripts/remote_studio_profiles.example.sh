#!/usr/bin/env bash

# Copy this file to scripts/remote_studio_profiles.local.sh and fill in the
# host aliases or SSH targets for your own environment. Prefer stable SSH
# aliases such as "primary" or "tertiary" over raw hostnames or IPs. Keep the
# .local file out of git.

# Default profile when --remote-profile is omitted.
export ARNIS_REMOTE_STUDIO_PROFILE="${ARNIS_REMOTE_STUDIO_PROFILE:-primary}"

# Primary development machine.
export ARNIS_REMOTE_STUDIO_HOST_PRIMARY="<primary-host>"
export ARNIS_REMOTE_STUDIO_ROOT_PRIMARY="__REMOTE_HOME__/.codex-remote-studio"
export ARNIS_REMOTE_STUDIO_BASE_ARNIS_PRIMARY="__REMOTE_HOME__/Projects/arnis-roblox"
export ARNIS_REMOTE_STUDIO_BASE_VSYNC_PRIMARY="__REMOTE_HOME__/Projects/vertigo-sync"

# Tertiary remote harness / overflow machine.
export ARNIS_REMOTE_STUDIO_HOST_TERTIARY="<tertiary-host>"
export ARNIS_REMOTE_STUDIO_ROOT_TERTIARY="__REMOTE_HOME__/.codex-remote-studio"
export ARNIS_REMOTE_STUDIO_BASE_ARNIS_TERTIARY="__REMOTE_HOME__/Projects/arnis-roblox"
export ARNIS_REMOTE_STUDIO_BASE_VSYNC_TERTIARY="__REMOTE_HOME__/Projects/vertigo-sync"

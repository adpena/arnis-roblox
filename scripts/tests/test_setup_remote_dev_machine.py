#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT_PATH = ROOT / "scripts" / "setup_remote_dev_machine.sh"


class SetupRemoteDevMachineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.text = SCRIPT_PATH.read_text(encoding="utf-8") if SCRIPT_PATH.exists() else ""

    def test_script_exists(self) -> None:
        self.assertTrue(SCRIPT_PATH.exists(), "expected remote dev machine setup script")

    def test_installs_remote_dev_tools_without_hardcoded_hosts(self) -> None:
        self.assertIn('ensure_brew_package tmux', self.text)
        self.assertIn('ensure_brew_package mosh', self.text)
        self.assertIn('ensure_brew_package uv', self.text)
        self.assertIn('ensure_tailscale', self.text)
        self.assertNotIn('primary.local', self.text)
        self.assertNotIn('tertiary.local', self.text)

    def test_writes_tmux_remote_dev_overlay_idempotently(self) -> None:
        self.assertIn('TMUX_REMOTE_CONF="$HOME/.tmux.remote-dev.conf"', self.text)
        self.assertIn('ensure_tmux_remote_conf()', self.text)
        self.assertIn('ensure_tmux_main_sources_remote_conf()', self.text)
        self.assertIn('if-shell \'[ -f ~/.tmux.remote-dev.conf ]\'', self.text)
        self.assertIn('grep -Fqx', self.text)

    def test_reports_tailscale_state_without_disabling_host_checks(self) -> None:
        self.assertIn('ensure_tailscale()', self.text)
        self.assertIn('tailscale cask install requires an interactive admin step', self.text)
        self.assertIn('tailscale CLI not found after install; complete the admin install step locally', self.text)
        self.assertIn('tailscale status', self.text)
        self.assertNotIn('StrictHostKeyChecking=no', self.text)


if __name__ == "__main__":
    unittest.main()

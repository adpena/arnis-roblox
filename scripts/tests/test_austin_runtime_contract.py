#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
BOOTSTRAP_PATH = ROOT / "roblox" / "src" / "ServerScriptService" / "BootstrapAustin.server.lua"
RUN_AUSTIN_PATH = ROOT / "roblox" / "src" / "ServerScriptService" / "ImportService" / "RunAustin.lua"


class AustinRuntimeContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.bootstrap_text = BOOTSTRAP_PATH.read_text(encoding="utf-8")
        cls.run_austin_text = RUN_AUSTIN_PATH.read_text(encoding="utf-8")

    def test_bootstrap_declares_observable_runtime_states_in_order(self) -> None:
        self.assertIn('local BOOTSTRAP_STATE_ATTR = "ArnisAustinBootstrapState"', self.bootstrap_text)
        self.assertIn('local BOOTSTRAP_STATE_ORDER_ATTR = "ArnisAustinBootstrapStateOrder"', self.bootstrap_text)
        self.assertIn('local BOOTSTRAP_FAILURE_ATTR = "ArnisAustinBootstrapFailure"', self.bootstrap_text)
        self.assertIn("loading_manifest = 1", self.bootstrap_text)
        self.assertIn("importing_startup = 2", self.bootstrap_text)
        self.assertIn("world_ready = 3", self.bootstrap_text)
        self.assertIn("streaming_ready = 4", self.bootstrap_text)
        self.assertIn("minimap_ready = 5", self.bootstrap_text)
        self.assertIn("gameplay_ready = 6", self.bootstrap_text)
        self.assertIn("failed = 7", self.bootstrap_text)
        bootstrap_ordered_states = [
            'setBootstrapState("world_ready")',
            'setBootstrapState("streaming_ready")',
            'setBootstrapState("minimap_ready")',
            'setBootstrapState("gameplay_ready")',
        ]
        bootstrap_positions = [self.bootstrap_text.find(marker) for marker in bootstrap_ordered_states]
        self.assertTrue(all(position >= 0 for position in bootstrap_positions), bootstrap_positions)
        self.assertEqual(bootstrap_positions, sorted(bootstrap_positions), bootstrap_positions)

        run_austin_ordered_states = [
            'onBootstrapState("loading_manifest")',
            'onBootstrapState("importing_startup")',
        ]
        run_austin_positions = [self.run_austin_text.find(marker) for marker in run_austin_ordered_states]
        self.assertTrue(all(position >= 0 for position in run_austin_positions), run_austin_positions)
        self.assertEqual(run_austin_positions, sorted(run_austin_positions), run_austin_positions)

    def test_duplicate_bootstrap_entry_is_a_failure_not_a_tolerated_noop(self) -> None:
        self.assertIn('local BOOTSTRAP_DUPLICATE_COUNT_ATTR = "ArnisAustinBootstrapDuplicateCount"', self.bootstrap_text)
        self.assertIn('local BOOTSTRAP_ENTRY_COUNT_ATTR = "ArnisAustinBootstrapEntryCount"', self.bootstrap_text)
        self.assertIn('local BOOTSTRAP_LAST_SCRIPT_PATH_ATTR = "ArnisAustinBootstrapLastScriptPath"', self.bootstrap_text)
        self.assertIn('Workspace:SetAttribute(BOOTSTRAP_ENTRY_COUNT_ATTR, entryCount)', self.bootstrap_text)
        self.assertIn('Workspace:SetAttribute(BOOTSTRAP_LAST_SCRIPT_PATH_ATTR, script:GetFullName())', self.bootstrap_text)
        self.assertIn('Workspace:SetAttribute(BOOTSTRAP_DUPLICATE_COUNT_ATTR, duplicateCount)', self.bootstrap_text)
        self.assertIn('setBootstrapState("failed", "duplicate bootstrap entry")', self.bootstrap_text)
        self.assertIn('"[BootstrapAustin] Duplicate bootstrap entry detected.', self.bootstrap_text)
        self.assertNotIn("Duplicate bootstrap attempt ignored", self.bootstrap_text)

    def test_run_austin_exposes_manifest_and_startup_import_phase_hooks(self) -> None:
        self.assertIn("function RunAustin.run(options)", self.run_austin_text)
        self.assertIn("options = options or {}", self.run_austin_text)
        self.assertIn("local onBootstrapState = options.onBootstrapState", self.run_austin_text)
        self.assertIn('onBootstrapState("loading_manifest")', self.run_austin_text)
        self.assertIn('onBootstrapState("importing_startup")', self.run_austin_text)
        self.assertIn('setPerfAttribute("Status", "loading_manifest")', self.run_austin_text)
        self.assertIn('setPerfAttribute("Status", "importing_startup")', self.run_austin_text)
        self.assertIn("local importConfig = options.importConfig", self.run_austin_text)
        self.assertIn("config = importConfig,", self.run_austin_text)

    def test_bootstrap_starts_minimap_as_an_explicit_phase_before_gameplay(self) -> None:
        self.assertIn("local MinimapService = require(script.Parent.ImportService.MinimapService)", self.bootstrap_text)
        self.assertIn("local startupImportConfig = table.clone(runtimeWorldConfig)", self.bootstrap_text)
        self.assertIn("startupImportConfig.EnableMinimap = false", self.bootstrap_text)
        self.assertIn("importConfig = startupImportConfig,", self.bootstrap_text)
        self.assertIn("MinimapService.Start()", self.bootstrap_text)
        self.assertIn('setBootstrapState("minimap_ready")', self.bootstrap_text)
        self.assertIn('Players.CharacterAutoLoads = true', self.bootstrap_text)
        minimap_ready_index = self.bootstrap_text.find('setBootstrapState("minimap_ready")')
        gameplay_ready_index = self.bootstrap_text.find('setBootstrapState("gameplay_ready")')
        character_enable_index = self.bootstrap_text.rfind("Players.CharacterAutoLoads = true")
        self.assertGreater(minimap_ready_index, -1)
        self.assertGreater(gameplay_ready_index, -1)
        self.assertGreater(character_enable_index, -1)
        self.assertLess(minimap_ready_index, character_enable_index)
        self.assertLess(minimap_ready_index, gameplay_ready_index)


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
RUNALL_PATH = ROOT / "roblox/src/ServerScriptService/Tests/RunAll.lua"
RUNALL_ENTRY_PATH = ROOT / "roblox/src/ServerScriptService/Tests/RunAllEntry.server.lua"
RUNALL_CONFIG_PATH = ROOT / "roblox/src/ServerScriptService/Tests/RunAllConfig.lua"


class RunAllFilterTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.runall_text = RUNALL_PATH.read_text(encoding="utf-8")
        cls.runall_entry_text = RUNALL_ENTRY_PATH.read_text(encoding="utf-8")
        cls.runall_config_text = RUNALL_CONFIG_PATH.read_text(encoding="utf-8")

    def test_runall_entry_exposes_optional_spec_filter(self) -> None:
        self.assertIn("local RunAllConfig = require(script.Parent.RunAllConfig)", self.runall_entry_text)
        self.assertIn("specNameFilter = RunAllConfig.specNameFilter", self.runall_entry_text)
        self.assertIn("runInEditMode = false", self.runall_config_text)
        self.assertIn("runInPlayMode = false", self.runall_config_text)
        self.assertIn('specNameFilter = ""', self.runall_config_text)

    def test_runall_supports_exact_spec_name_filtering(self) -> None:
        self.assertIn("function RunAll.run(options)", self.runall_text)
        self.assertIn(
            "local specNameFilter = normalizeSpecNameFilter(options and options.specNameFilter or nil)",
            self.runall_text,
        )
        self.assertIn("if specNameFilter ~= nil then", self.runall_text)
        self.assertIn("local function normalizeSpecNameFilter", self.runall_text)
        self.assertIn('string.sub(specNameFilter, -4) == ".lua"', self.runall_text)
        self.assertIn('specNameFilter = string.sub(specNameFilter, 1, -5)', self.runall_text)
        self.assertIn("moduleScript.Name == specNameFilter", self.runall_text)


if __name__ == "__main__":
    unittest.main()

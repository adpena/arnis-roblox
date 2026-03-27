#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
BUILDER_PATH = ROOT / "roblox/src/ServerScriptService/StudioPreview/AustinPreviewBuilder.lua"


class AustinPreviewBuilderContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.text = BUILDER_PATH.read_text(encoding="utf-8")

    def test_builder_waits_for_preview_request_and_telemetry_modules(self) -> None:
        self.assertIn('WaitForChild("AustinPreviewRequest")', self.text)
        self.assertIn('WaitForChild("AustinPreviewTelemetry")', self.text)
        self.assertNotIn("require(script.Parent.AustinPreviewRequest)", self.text)
        self.assertNotIn("require(script.Parent.AustinPreviewTelemetry)", self.text)


if __name__ == "__main__":
    unittest.main()

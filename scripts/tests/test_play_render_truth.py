from __future__ import annotations

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[2]
BUILDING_BUILDER = ROOT / "roblox" / "src" / "ServerScriptService" / "ImportService" / "Builders" / "BuildingBuilder.lua"
IMPORT_SERVICE = ROOT / "roblox" / "src" / "ServerScriptService" / "ImportService" / "init.lua"
IMPORT_SIGNATURES = ROOT / "roblox" / "src" / "ServerScriptService" / "ImportService" / "ImportSignatures.lua"
STREAMING_SERVICE = ROOT / "roblox" / "src" / "ServerScriptService" / "ImportService" / "StreamingService.lua"


class PlayRenderTruthTests(unittest.TestCase):
    def test_startup_import_and_streaming_share_signature_source(self) -> None:
        self.assertTrue(
            IMPORT_SIGNATURES.exists(),
            "expected ImportSignatures.lua to exist so startup import and streaming share one signature truth",
        )

        import_service_source = IMPORT_SERVICE.read_text(encoding="utf-8")
        streaming_source = STREAMING_SERVICE.read_text(encoding="utf-8")

        self.assertIn("ImportSignatures", import_service_source)
        self.assertIn("ImportSignatures", streaming_source)
        self.assertRegex(
            import_service_source,
            r"configSignature\\s*=\\s*resolvedSignatures\\.configSignature",
            "expected ImportService to register startup chunks with shared config signatures",
        )
        self.assertRegex(
            import_service_source,
            r"layerSignatures\\s*=\\s*resolvedSignatures\\.layerSignatures",
            "expected ImportService to register startup chunks with shared layer signatures",
        )
        self.assertRegex(
            streaming_source,
            r"ImportSignatures\\.[A-Za-z_]+\\(",
            "expected StreamingService to derive signatures from the shared ImportSignatures helper",
        )

    def test_roof_only_builder_uses_rooftop_base_metadata(self) -> None:
        source = BUILDING_BUILDER.read_text(encoding="utf-8")

        self.assertRegex(
            source,
            r"minHeight",
            "expected BuildingBuilder roof-only path to consult rooftop base metadata when present",
        )
        self.assertRegex(
            source,
            r"resolveRoofOnly[A-Za-z]+",
            "expected an explicit roof-only metric helper instead of reusing generic full-height shell values",
        )


if __name__ == "__main__":
    unittest.main()

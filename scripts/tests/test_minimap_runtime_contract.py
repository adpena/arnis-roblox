#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
IMPORT_SERVICE_PATH = ROOT / "roblox" / "src" / "ServerScriptService" / "ImportService" / "init.lua"
WORLD_STATE_APPLIER_PATH = (
    ROOT / "roblox" / "src" / "ServerScriptService" / "ImportService" / "WorldStateApplier.lua"
)
SERVER_MINIMAP_PATH = ROOT / "roblox" / "src" / "ServerScriptService" / "ImportService" / "MinimapService.lua"
CLIENT_MINIMAP_PATH = (
    ROOT / "roblox" / "src" / "StarterPlayer" / "StarterPlayerScripts" / "MinimapController.client.lua"
)


class MinimapRuntimeContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.import_service_text = IMPORT_SERVICE_PATH.read_text(encoding="utf-8")
        cls.world_state_text = WORLD_STATE_APPLIER_PATH.read_text(encoding="utf-8")
        cls.server_minimap_text = SERVER_MINIMAP_PATH.read_text(encoding="utf-8")
        cls.client_minimap_text = (
            CLIENT_MINIMAP_PATH.read_text(encoding="utf-8") if CLIENT_MINIMAP_PATH.exists() else ""
        )

    def test_import_service_registers_minimap_data_on_chunk_folders(self) -> None:
        self.assertIn("MinimapService.RegisterChunk(chunkFolder, chunk)", self.import_service_text)
        self.assertIn('worldRootName = worldRootName,', self.import_service_text)
        self.assertIn('startMinimap = true,', self.import_service_text)

    def test_world_state_applier_passes_world_root_name_to_minimap_start(self) -> None:
        self.assertIn("minimapService.Start({", self.world_state_text)
        self.assertIn("worldRootName = resolvedOptions.worldRootName,", self.world_state_text)

    def test_server_minimap_stops_owning_camera_and_gui(self) -> None:
        self.assertIn("chunkFolder:SetAttribute(CHUNK_JSON_ATTR", self.server_minimap_text)
        self.assertIn("Workspace:SetAttribute(WORLD_ROOT_ATTR", self.server_minimap_text)
        self.assertNotIn("workspace.CurrentCamera", self.server_minimap_text)
        self.assertNotIn("UserInputService", self.server_minimap_text)
        self.assertNotIn("CreateGui", self.server_minimap_text)
        self.assertNotIn("ScreenGui", self.server_minimap_text)

    def test_client_minimap_owns_camera_input_and_gui(self) -> None:
        self.assertTrue(CLIENT_MINIMAP_PATH.exists(), "expected a client minimap controller")
        self.assertIn("Workspace.CurrentCamera", self.client_minimap_text)
        self.assertIn("UserInputService", self.client_minimap_text)
        self.assertIn('screenGui.Name = "MinimapGui"', self.client_minimap_text)
        self.assertIn("folder:GetAttribute(CHUNK_JSON_ATTR)", self.client_minimap_text)
        self.assertIn("Workspace:GetAttribute(WORLD_ROOT_ATTR)", self.client_minimap_text)

    def test_client_minimap_keeps_world_north_up_and_rotates_only_player_heading(self) -> None:
        self.assertIn("local function worldToPixel(worldX, worldZ, camX, camZ)", self.client_minimap_text)
        self.assertIn("renderMap(camPos.X, camPos.Z)", self.client_minimap_text)
        self.assertNotIn("renderMap(camPos.X, camPos.Z, camYaw)", self.client_minimap_text)
        self.assertIn("drawPlayerHeading(camYaw)", self.client_minimap_text)

    def test_client_minimap_renders_footprints_from_polygon_points_not_world_bounding_boxes(self) -> None:
        self.assertIn("local function drawFilledPolygon(pixelPoints, color)", self.client_minimap_text)
        self.assertIn("local function footprintToPixelPoints(footprint, ox, oz, camX, camZ)", self.client_minimap_text)
        self.assertIn("drawFilledPolygon(footprintToPixelPoints(", self.client_minimap_text)
        self.assertNotIn("local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge", self.client_minimap_text)


if __name__ == "__main__":
    unittest.main()

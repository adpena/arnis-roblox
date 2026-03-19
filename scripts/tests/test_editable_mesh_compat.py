from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
ROAD_BUILDER = ROOT / "roblox" / "src" / "ServerScriptService" / "ImportService" / "Builders" / "RoadBuilder.lua"
BUILDING_BUILDER = ROOT / "roblox" / "src" / "ServerScriptService" / "ImportService" / "Builders" / "BuildingBuilder.lua"


class EditableMeshCompatTests(unittest.TestCase):
    def test_mesh_builders_guard_vertex_normal_api(self) -> None:
        for path in (ROAD_BUILDER, BUILDING_BUILDER):
            source = path.read_text()
            self.assertIn("local function trySetVertexNormal", source, path.name)
            self.assertIn("pcall(function()", source, path.name)
            self.assertIn("trySetVertexNormal(mesh,", source, path.name)
            self.assertEqual(source.count("mesh:SetVertexNormal("), 1, path.name)

    def test_road_builder_falls_back_to_default_mesh_materials(self) -> None:
        source = ROAD_BUILDER.read_text()
        self.assertIn("local function resolvePlannedRoadMaterial", source)
        self.assertIn("return material or Enum.Material.Asphalt", source)
        self.assertIn("self.material = resolvePlannedRoadMaterial(material)", source)

    def test_mesh_builders_create_mesh_parts_from_editable_mesh_content(self) -> None:
        for path in (ROAD_BUILDER, BUILDING_BUILDER):
            source = path.read_text()
            self.assertIn("AssetService:CreateMeshPartAsync(Content.fromObject(mesh))", source, path.name)
            self.assertNotIn(":ApplyMesh(mesh)", source, path.name)


if __name__ == "__main__":
    unittest.main()

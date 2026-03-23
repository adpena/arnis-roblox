return function()
    local Workspace = game:GetService("Workspace")
    local ImportService = require(script.Parent.Parent.ImportService)
    local Assert = require(script.Parent.Assert)

    local manifest = {
        schemaVersion = "0.4.0",
        meta = {
            worldName = "FlatShellMeshRoofTruth",
            generator = "test",
            source = "unit",
            metersPerStud = 0.3,
            chunkSizeStuds = 256,
            totalFeatures = 1,
        },
        chunks = {
            {
                id = "0_0",
                originStuds = { x = 0, y = 0, z = 0 },
                terrain = {
                    cellSizeStuds = 16,
                    width = 16,
                    depth = 16,
                    heights = table.create(16 * 16, 0),
                    material = "Grass",
                },
                roads = {},
                rails = {},
                buildings = {
                    {
                        id = "flat_shell_mesh_office",
                        footprint = {
                            { x = 0, z = 0 },
                            { x = 24, z = 0 },
                            { x = 24, z = 18 },
                            { x = 0, z = 18 },
                        },
                        baseY = 0,
                        height = 20,
                        levels = 4,
                        roof = "flat",
                        usage = "office",
                        material = "Concrete",
                    },
                },
                water = {},
                props = {},
                landuse = {},
                barriers = {},
            },
        },
    }

    local worldRootName = "GeneratedWorld_FlatShellMeshRoofTruth"
    ImportService.ImportManifest(manifest, {
        clearFirst = true,
        worldRootName = worldRootName,
        config = {
            BuildingMode = "shellMesh",
            TerrainMode = "none",
            RoadMode = "none",
            WaterMode = "none",
            LanduseMode = "none",
        },
    })

    local worldRoot = Workspace:FindFirstChild(worldRootName)
    Assert.truthy(worldRoot, "expected flat shell mesh roof truth world root")

    local building = worldRoot
        :FindFirstChild("0_0")
        :FindFirstChild("Buildings")
        :FindFirstChild("flat_shell_mesh_office")
    Assert.truthy(building, "expected flat shell mesh building")

    local shellFolder = building:FindFirstChild("Shell")
    Assert.truthy(shellFolder, "expected shell folder")

    local roofParts = {}
    for _, descendant in ipairs(shellFolder:GetDescendants()) do
        if descendant:IsA("BasePart") and string.find(descendant.Name, "_roof", 1, true) then
            roofParts[#roofParts + 1] = descendant
        end
    end

    Assert.truthy(#roofParts >= 1, "expected shellMesh flat roof path to emit direct roof geometry")
    Assert.falsy(
        building:GetAttribute("ArnisImportHasMergedRoofGeometry") == true,
        "expected direct flat roof geometry to replace merged-roof-only evidence"
    )

    worldRoot:Destroy()
end

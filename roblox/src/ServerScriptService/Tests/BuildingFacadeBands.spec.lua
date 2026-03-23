return function()
    local Workspace = game:GetService("Workspace")
    local CollectionService = game:GetService("CollectionService")
    local ImportService = require(script.Parent.Parent.ImportService)
    local ChunkLoader = require(script.Parent.Parent.ImportService.ChunkLoader)
    local Assert = require(script.Parent.Assert)

    local manifest = {
        schemaVersion = "0.4.0",
        meta = {
            worldName = "FacadeBands",
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
                        id = "office_tower",
                        footprint = {
                            { x = 0, z = 0 },
                            { x = 32, z = 0 },
                            { x = 32, z = 24 },
                            { x = 0, z = 24 },
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

    local worldRootName = "GeneratedWorld_FacadeBands"
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
    Assert.truthy(worldRoot, "expected facade bands world root")

    local building =
        worldRoot:FindFirstChild("0_0"):FindFirstChild("Buildings"):FindFirstChild("office_tower")
    Assert.truthy(building, "expected office tower")
    local detailFolder = building:FindFirstChild("Detail")
    Assert.truthy(detailFolder, "expected shared detail folder under office tower")
    Assert.near(
        building:GetAttribute("ArnisImportBuildingHeight"),
        20,
        1e-6,
        "expected building shell metadata to retain resolved height"
    )
    Assert.equal(
        detailFolder:GetAttribute("ArnisLodGroupKind"),
        "detail",
        "expected detail folder lod group kind"
    )
    local chunkEntry = ChunkLoader.GetChunkEntry("0_0")
    Assert.truthy(chunkEntry, "expected chunk entry for facade bands world")
    Assert.truthy(
        chunkEntry.lodGroups and #chunkEntry.lodGroups.detail >= 1,
        "expected registered detail lod groups"
    )
    Assert.truthy(
        chunkEntry.reactives and #chunkEntry.reactives.nightWindows == 12,
        "expected facade bands to register exact night-window reactives"
    )

    local facadeBands = {}
    local windowSills = {}
    for _, child in ipairs(detailFolder:GetChildren()) do
        if child:IsA("Part") and string.find(child.Name, "_facade_", 1, true) then
            facadeBands[#facadeBands + 1] = child
        elseif child:IsA("Part") and child.Name == "WindowSill" then
            windowSills[#windowSills + 1] = child
        end
    end

    Assert.equal(#facadeBands, 12, "expected one facade band per edge per upper floor")
    Assert.equal(
        #windowSills,
        0,
        "expected facade sill geometry to be merged instead of emitted per band"
    )
    for _, band in ipairs(facadeBands) do
        Assert.falsy(
            CollectionService:HasTag(band, "LOD_Detail"),
            "expected facade bands to rely on grouped detail ownership"
        )
        Assert.truthy(
            (band:GetAttribute("ArnisFacadePaneCount") or 0) >= 1,
            "expected facade bands to retain deterministic pane density metadata"
        )
    end

    worldRoot:Destroy()
end

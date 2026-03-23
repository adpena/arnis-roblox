return function()
    local Workspace = game:GetService("Workspace")
    local ImportService = require(script.Parent.Parent.ImportService)
    local Assert = require(script.Parent.Assert)

    local manifest = {
        schemaVersion = "0.4.0",
        meta = {
            worldName = "PreviewVisualOnlyMeshCollision",
            generator = "test",
            source = "unit",
            metersPerStud = 1.0,
            chunkSizeStuds = 256,
            totalFeatures = 2,
        },
        chunks = {
            {
                id = "0_0",
                originStuds = { x = 0, y = 0, z = 0 },
                roads = {
                    {
                        id = "preview_road",
                        kind = "secondary",
                        material = "Asphalt",
                        widthStuds = 16,
                        hasSidewalk = true,
                        points = {
                            { x = 32, y = 0, z = 64 },
                            { x = 224, y = 0, z = 64 },
                        },
                    },
                },
                rails = {},
                buildings = {
                    {
                        id = "preview_building",
                        footprint = {
                            { x = 80, z = 96 },
                            { x = 128, z = 96 },
                            { x = 128, z = 144 },
                            { x = 80, z = 144 },
                        },
                        baseY = 0,
                        height = 24,
                        levels = 5,
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

    local worldRootName = "GeneratedWorld_PreviewVisualOnlyMeshCollision"
    ImportService.ImportManifest(manifest, {
        clearFirst = true,
        worldRootName = worldRootName,
        meshCollisionPolicy = "visual_only",
        config = {
            TerrainMode = "none",
            RoadMode = "mesh",
            BuildingMode = "shellMesh",
            WaterMode = "none",
            LanduseMode = "none",
            EnableDayNightCycle = false,
            EnableAtmosphere = false,
            EnableMinimap = false,
        },
    })

    local worldRoot = Workspace:FindFirstChild(worldRootName)
    Assert.truthy(worldRoot, "expected preview visual-only world root")
    local chunkFolder = worldRoot:FindFirstChild("0_0")
    Assert.truthy(chunkFolder, "expected chunk folder")

    local roadMeshParts = {}
    for _, descendant in ipairs(chunkFolder:FindFirstChild("Roads"):GetDescendants()) do
        if descendant:IsA("MeshPart") then
            roadMeshParts[#roadMeshParts + 1] = descendant
        end
    end

    local buildingMeshParts = {}
    for _, descendant in ipairs(chunkFolder:FindFirstChild("Buildings"):GetDescendants()) do
        if descendant:IsA("MeshPart") then
            buildingMeshParts[#buildingMeshParts + 1] = descendant
        end
    end

    Assert.truthy(#roadMeshParts >= 1, "expected preview road mesh parts")
    Assert.truthy(#buildingMeshParts >= 1, "expected preview building mesh parts")

    for _, part in ipairs(roadMeshParts) do
        Assert.falsy(part.CanCollide, "expected preview road mesh parts to disable collision")
        Assert.falsy(part.CanQuery, "expected preview road mesh parts to disable query")
    end

    for _, part in ipairs(buildingMeshParts) do
        Assert.falsy(part.CanCollide, "expected preview building mesh parts to disable collision")
        Assert.falsy(part.CanQuery, "expected preview building mesh parts to disable query")
    end

    worldRoot:Destroy()
end

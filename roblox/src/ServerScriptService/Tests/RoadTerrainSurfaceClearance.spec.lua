return function()
    local Workspace = game:GetService("Workspace")
    local ImportService = require(script.Parent.Parent.ImportService)
    local GroundSampler = require(script.Parent.Parent.ImportService.GroundSampler)
    local Assert = require(script.Parent.Assert)

    local terrainHeights = table.create(16 * 16, 20)
    local manifest = {
        schemaVersion = "0.4.0",
        meta = {
            worldName = "RoadTerrainSurfaceClearance",
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
                terrain = {
                    cellSizeStuds = 16,
                    width = 16,
                    depth = 16,
                    heights = terrainHeights,
                    material = "Grass",
                },
                roads = {
                    {
                        id = "sunken_road",
                        kind = "secondary",
                        material = "Asphalt",
                        widthStuds = 8,
                        hasSidewalk = false,
                        points = {
                            { x = 32, y = 18, z = 128 },
                            { x = 224, y = 18, z = 128 },
                        },
                    },
                },
                rails = {},
                buildings = {},
                water = {},
                props = {},
                landuse = {},
                barriers = {},
            },
        },
    }

    local worldRootName = "GeneratedWorld_RoadTerrainSurfaceClearance"
    ImportService.ImportManifest(manifest, {
        clearFirst = true,
        worldRootName = worldRootName,
        config = {
            TerrainMode = "paint",
            RoadMode = "mesh",
            BuildingMode = "none",
            WaterMode = "none",
            LanduseMode = "none",
        },
    })

    local worldRoot = Workspace:FindFirstChild(worldRootName)
    Assert.truthy(worldRoot, "expected world root")
    local roadsFolder = worldRoot:FindFirstChild("0_0"):FindFirstChild("Roads")
    Assert.truthy(roadsFolder, "expected roads folder")

    local roadSurface = nil
    for _, child in ipairs(roadsFolder:GetDescendants()) do
        if child:IsA("BasePart") and child:GetAttribute("ArnisRoadSurfaceRole") == "road" then
            roadSurface = child
            break
        end
    end

    Assert.truthy(roadSurface, "expected mesh road surface")

    local terrainGroundY = GroundSampler.sampleWorldHeight(manifest.chunks[1], 128, 128)
    Assert.near(terrainGroundY, 20, 0.001, "expected test terrain height reference")
    local overlapProbe = Workspace:GetPartBoundsInBox(
        CFrame.new(128, terrainGroundY + 0.5, 128),
        Vector3.new(16, 4, 16)
    )
    local roadFoundInProbe = false
    for _, part in ipairs(overlapProbe) do
        if part == roadSurface then
            roadFoundInProbe = true
            break
        end
    end
    local ray = Workspace:Raycast(Vector3.new(128, 100, 128), Vector3.new(0, -200, 0))
    Assert.truthy(ray, "expected raycast hit above road corridor")
    Assert.truthy(
        ray.Instance == roadSurface,
        ("expected road surface to be the topmost hit above terrain; got %s instead | roadInProbe=%s roadPos=%s roadSize=%s canQuery=%s"):format(
            ray.Instance and ray.Instance:GetFullName() or "nil",
            tostring(roadFoundInProbe),
            tostring(roadSurface.Position),
            tostring(roadSurface.Size),
            tostring(roadSurface.CanQuery)
        )
    )
    Assert.truthy(
        ray.Position.Y > terrainGroundY,
        ("expected road surface hit to sit above terrain; got roadY=%s terrainY=%s"):format(
            tostring(ray.Position.Y),
            tostring(terrainGroundY)
        )
    )

    worldRoot:Destroy()
end

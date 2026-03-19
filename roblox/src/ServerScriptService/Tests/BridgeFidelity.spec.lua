return function()
    local Workspace = game:GetService("Workspace")
    local ImportService = require(script.Parent.Parent.ImportService)
    local Assert = require(script.Parent.Assert)

    local terrainHeights = table.create(16 * 16, 0)
    local manifest = {
        schemaVersion = "0.2.0",
        meta = {
            worldName = "BridgeFidelity",
            generator = "test",
            source = "unit",
            metersPerStud = 1.0,
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
                    heights = terrainHeights,
                    material = "Grass",
                },
                roads = {
                    {
                        id = "bridge_road",
                        kind = "secondary",
                        material = "Concrete",
                        widthStuds = 12,
                        hasSidewalk = false,
                        points = {
                            { x = 32, y = 10, z = 32 },
                            { x = 224, y = 10, z = 160 },
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

    local worldRootName = "GeneratedWorld_BridgeFidelity"
    ImportService.ImportManifest(manifest, {
        clearFirst = true,
        worldRootName = worldRootName,
    })

    local roadsFolder = Workspace:FindFirstChild(worldRootName):FindFirstChild("0_0"):FindFirstChild("Roads")
    Assert.truthy(roadsFolder, "expected roads folder for elevated bridge geometry")

    local deck = roadsFolder:FindFirstChildWhichIsA("Part")
    Assert.truthy(deck, "expected bridge deck part")

    local supportCount = 0
    local railPostCount = 0
    for _, child in ipairs(roadsFolder:GetChildren()) do
        if child.Name == "BridgeSupport" then
            supportCount += 1
            Assert.truthy(child.Size.Y > 2, "expected bridge support pillar to reach toward terrain")
        elseif child.Name == "BridgeRailPost" then
            railPostCount += 1
        end
    end

    Assert.truthy(supportCount >= 1, "expected at least one bridge support pillar")
    Assert.truthy(railPostCount >= 2, "expected guardrail posts on elevated bridge")

    Workspace:FindFirstChild(worldRootName):Destroy()
end

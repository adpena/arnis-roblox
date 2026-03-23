return function()
    local Workspace = game:GetService("Workspace")
    local ImportService = require(script.Parent.Parent.ImportService)
    local Assert = require(script.Parent.Assert)

    local function makeManifest(roadOverrides)
        local terrainHeights = table.create(16 * 16, 0)
        local road = {
            id = "bridge_road",
            kind = "secondary",
            material = "Asphalt",
            widthStuds = 12,
            hasSidewalk = false,
            elevated = true,
            points = {
                { x = 32, y = 10, z = 32 },
                { x = 224, y = 10, z = 160 },
            },
        }

        for key, value in pairs(roadOverrides or {}) do
            road[key] = value
        end

        return {
            schemaVersion = "0.4.0",
            meta = {
                worldName = "BridgeFidelity",
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
                        heights = terrainHeights,
                        material = "Grass",
                    },
                    roads = { road },
                    rails = {},
                    buildings = {},
                    water = {},
                    props = {},
                    landuse = {},
                    barriers = {},
                },
            },
        }
    end

    local function importBridge(worldRootName, roadOverrides, config)
        ImportService.ImportManifest(makeManifest(roadOverrides), {
            clearFirst = true,
            worldRootName = worldRootName,
            config = config,
        })

        local roadsFolder =
            Workspace:FindFirstChild(worldRootName):FindFirstChild("0_0"):FindFirstChild("Roads")
        Assert.truthy(roadsFolder, "expected roads folder for elevated bridge geometry")

        local deck = nil
        for _, child in ipairs(roadsFolder:GetDescendants()) do
            if
                child:IsA("BasePart")
                and child.Name ~= "BridgeSupport"
                and child.Name ~= "BridgeRailPost"
            then
                deck = child
                break
            end
        end
        Assert.truthy(deck, "expected bridge deck part")

        local supportCount = 0
        local railPostCount = 0
        for _, child in ipairs(roadsFolder:GetDescendants()) do
            if child.Name == "BridgeSupport" then
                supportCount += 1
                Assert.truthy(
                    child.Size.Y > 2,
                    "expected bridge support pillar to reach toward terrain"
                )
            elseif child.Name == "BridgeRailPost" then
                railPostCount += 1
            end
        end

        Assert.truthy(supportCount >= 1, "expected at least one bridge support pillar")
        Assert.truthy(railPostCount >= 2, "expected guardrail posts on elevated bridge")

        return deck
    end

    local meshDeck = importBridge("GeneratedWorld_BridgeFidelityMesh", {}, {
        TerrainMode = "paint",
        RoadMode = "mesh",
        BuildingMode = "none",
        WaterMode = "none",
        LanduseMode = "none",
    })
    Assert.equal(
        Enum.Material.Asphalt,
        meshDeck.Material,
        "expected mesh-mode bridges to fall back to road material"
    )
    Workspace:FindFirstChild("GeneratedWorld_BridgeFidelityMesh"):Destroy()
end

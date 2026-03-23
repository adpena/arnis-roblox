return function()
    local Workspace = game:GetService("Workspace")

    local ImportService = require(script.Parent.Parent.ImportService)
    local Assert = require(script.Parent.Assert)

    local function countBuildingModels(worldRootName)
        local worldRoot = Workspace:FindFirstChild(worldRootName)
        Assert.truthy(worldRoot, "expected generated world root")

        local chunkFolder = worldRoot:FindFirstChild("0_0")
        Assert.truthy(chunkFolder, "expected chunk folder")

        local buildingsFolder = chunkFolder:FindFirstChild("Buildings")
        Assert.truthy(buildingsFolder, "expected Buildings folder")

        local count = 0
        for _, child in ipairs(buildingsFolder:GetDescendants()) do
            if child:IsA("Model") then
                count += 1
            end
        end
        return count, buildingsFolder
    end

    local function hasDescendantNamed(root, name)
        for _, descendant in ipairs(root:GetDescendants()) do
            if descendant.Name == name then
                return true
            end
        end
        return false
    end

    local function destroyWorldRoot(worldRootName)
        local worldRoot = Workspace:FindFirstChild(worldRootName)
        if worldRoot then
            worldRoot:Destroy()
        end
    end

    local chunk = {
        id = "0_0",
        originStuds = { x = 0, y = 0, z = 0 },
        roads = {},
        rails = {},
        buildings = {
            {
                id = "building_west",
                material = "Brick",
                baseY = 0,
                height = 24,
                roof = "flat",
                footprint = {
                    { x = 16, z = 32 },
                    { x = 48, z = 32 },
                    { x = 48, z = 64 },
                    { x = 16, z = 64 },
                },
            },
            {
                id = "building_east",
                material = "Brick",
                baseY = 0,
                height = 24,
                roof = "flat",
                footprint = {
                    { x = 176, z = 32 },
                    { x = 208, z = 32 },
                    { x = 208, z = 64 },
                    { x = 176, z = 64 },
                },
            },
        },
        water = {},
        props = {},
        landuse = {},
        barriers = {},
        subplans = {
            {
                id = "barriers",
                layer = "barriers",
                featureCount = 0,
                streamingCost = 0,
            },
            {
                id = "buildings:west",
                layer = "buildings",
                featureCount = 1,
                streamingCost = 12,
                bounds = {
                    minX = 0,
                    minY = 0,
                    maxX = 128,
                    maxY = 128,
                },
            },
            {
                id = "buildings:east",
                layer = "buildings",
                featureCount = 1,
                streamingCost = 12,
                bounds = {
                    minX = 128,
                    minY = 0,
                    maxX = 256,
                    maxY = 128,
                },
            },
        },
    }

    local config = {
        TerrainMode = "none",
        RoadMode = "none",
        BuildingMode = "shellParts",
        WaterMode = "none",
        LanduseMode = "terrain",
    }

    local fullWorldRootName = "GeneratedWorld_SubplanSpatialBounds_Full"
    local stagedWorldRootName = "GeneratedWorld_SubplanSpatialBounds_Staged"

    ImportService.ResetSubplanState(chunk.id)
    ImportService.ImportChunk(chunk, {
        worldRootName = fullWorldRootName,
        config = config,
    })
    local fullCount = countBuildingModels(fullWorldRootName)

    ImportService.ResetSubplanState(chunk.id)
    ImportService.ImportChunkSubplan(chunk, chunk.subplans[1], {
        worldRootName = stagedWorldRootName,
        config = config,
    })
    ImportService.ImportChunkSubplan(chunk, chunk.subplans[2], {
        worldRootName = stagedWorldRootName,
        config = config,
    })

    local westCount, stagedBuildingsFolder = countBuildingModels(stagedWorldRootName)
    Assert.equal(westCount, 1, "expected bounded west subplan to import only one building")
    Assert.truthy(
        hasDescendantNamed(stagedBuildingsFolder, "building_west"),
        "expected west subplan to import west building"
    )
    Assert.falsy(
        hasDescendantNamed(stagedBuildingsFolder, "building_east"),
        "expected west subplan to exclude east building"
    )

    ImportService.ImportChunkSubplan(chunk, chunk.subplans[3], {
        worldRootName = stagedWorldRootName,
        config = config,
    })

    local stagedCount, refreshedBuildingsFolder = countBuildingModels(stagedWorldRootName)
    Assert.equal(
        stagedCount,
        2,
        "expected sibling bounded subplan imports to accumulate additively"
    )
    Assert.truthy(
        hasDescendantNamed(refreshedBuildingsFolder, "building_west"),
        "expected east import to preserve west building output"
    )
    Assert.truthy(
        hasDescendantNamed(refreshedBuildingsFolder, "building_east"),
        "expected east import to add east building output"
    )
    Assert.equal(
        stagedCount,
        fullCount,
        "expected bounded staged import to match whole chunk building count"
    )

    ImportService.ImportChunkSubplan(chunk, chunk.subplans[2], {
        worldRootName = stagedWorldRootName,
        config = config,
    })
    local replayCount = countBuildingModels(stagedWorldRootName)
    Assert.equal(
        replayCount,
        2,
        "expected repeated bounded subplan import to overwrite, not duplicate"
    )

    destroyWorldRoot(fullWorldRootName)
    destroyWorldRoot(stagedWorldRootName)
    ImportService.ResetSubplanState(chunk.id)
end

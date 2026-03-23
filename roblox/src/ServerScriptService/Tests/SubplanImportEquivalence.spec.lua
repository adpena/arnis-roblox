return function()
    local Workspace = game:GetService("Workspace")

    local ImportService = require(script.Parent.Parent.ImportService)
    local Assert = require(script.Parent.Assert)

    local function countDescendantsByClass(root)
        local counts = {
            folders = 0,
            parts = 0,
            models = 0,
            attachments = 0,
        }

        for _, descendant in ipairs(root:GetDescendants()) do
            if descendant:IsA("Folder") then
                counts.folders += 1
            elseif descendant:IsA("BasePart") then
                counts.parts += 1
            elseif descendant:IsA("Model") then
                counts.models += 1
            elseif descendant:IsA("Attachment") then
                counts.attachments += 1
            end
        end

        return counts
    end

    local function snapshotChunk(worldRootName)
        local worldRoot = Workspace:FindFirstChild(worldRootName)
        Assert.truthy(worldRoot, "expected generated world root")

        local chunkFolder = worldRoot:FindFirstChild("0_0")
        Assert.truthy(chunkFolder, "expected chunk folder")

        return {
            roadsChildren = #(chunkFolder:FindFirstChild("Roads"):GetChildren()),
            buildingsChildren = #(chunkFolder:FindFirstChild("Buildings"):GetChildren()),
            landuseChildren = #(chunkFolder:FindFirstChild("Landuse"):GetChildren()),
            barriersChildren = #(chunkFolder:FindFirstChild("Barriers"):GetChildren()),
            waterChildren = #(chunkFolder:FindFirstChild("Water"):GetChildren()),
            propsChildren = #(chunkFolder:FindFirstChild("Props"):GetChildren()),
            descendantCounts = countDescendantsByClass(chunkFolder),
        }
    end

    local chunk = {
        id = "0_0",
        originStuds = { x = 0, y = 0, z = 0 },
        roads = {
            {
                id = "road_1",
                kind = "secondary",
                material = "Asphalt",
                widthStuds = 16,
                hasSidewalk = true,
                points = {
                    { x = 16, y = 0, z = 64 },
                    { x = 240, y = 0, z = 64 },
                },
            },
        },
        rails = {},
        buildings = {
            {
                id = "building_1",
                material = "Brick",
                baseY = 0,
                height = 24,
                roof = "flat",
                footprint = {
                    { x = 96, z = 112 },
                    { x = 160, z = 112 },
                    { x = 160, z = 176 },
                    { x = 96, z = 176 },
                },
            },
        },
        water = {
            {
                id = "water_1",
                kind = "pond",
                footprint = {
                    { x = 176, z = 176 },
                    { x = 224, z = 176 },
                    { x = 224, z = 224 },
                    { x = 176, z = 224 },
                },
            },
        },
        props = {
            {
                id = "tree_1",
                kind = "tree",
                position = { x = 48, y = 0, z = 176 },
            },
        },
        landuse = {
            {
                id = "park_1",
                kind = "park",
                footprint = {
                    { x = 0, z = 0 },
                    { x = 256, z = 0 },
                    { x = 256, z = 96 },
                    { x = 0, z = 96 },
                },
            },
        },
        barriers = {
            {
                id = "barrier_1",
                kind = "fence",
                points = {
                    { x = 64, y = 0, z = 192 },
                    { x = 160, y = 0, z = 192 },
                },
            },
        },
        subplans = {
            { id = "landuse", layer = "landuse", featureCount = 1, streamingCost = 8 },
            { id = "roads", layer = "roads", featureCount = 1, streamingCost = 12 },
            { id = "barriers", layer = "barriers", featureCount = 1, streamingCost = 4 },
            { id = "buildings", layer = "buildings", featureCount = 1, streamingCost = 15 },
            { id = "water", layer = "water", featureCount = 1, streamingCost = 5 },
            { id = "props", layer = "props", featureCount = 1, streamingCost = 3 },
        },
    }

    local config = {
        TerrainMode = "none",
        RoadMode = "mesh",
        BuildingMode = "shellParts",
        WaterMode = "mesh",
        LanduseMode = "terrain",
    }

    local fullWorldRootName = "GeneratedWorld_SubplanEquivalence_Full"
    local stagedWorldRootName = "GeneratedWorld_SubplanEquivalence_Staged"

    ImportService.ResetSubplanState(chunk.id)
    ImportService.ImportChunk(chunk, {
        worldRootName = fullWorldRootName,
        config = config,
    })
    local fullSnapshot = snapshotChunk(fullWorldRootName)

    ImportService.ResetSubplanState(chunk.id)
    for _, subplan in ipairs(chunk.subplans) do
        ImportService.ImportChunkSubplan(chunk, subplan, {
            worldRootName = stagedWorldRootName,
            config = config,
        })
    end

    local stagedSnapshot = snapshotChunk(stagedWorldRootName)

    Assert.equal(
        stagedSnapshot.roadsChildren,
        fullSnapshot.roadsChildren,
        "expected staged road folder child count to match whole chunk import"
    )
    Assert.equal(
        stagedSnapshot.buildingsChildren,
        fullSnapshot.buildingsChildren,
        "expected staged building folder child count to match whole chunk import"
    )
    Assert.equal(
        stagedSnapshot.landuseChildren,
        fullSnapshot.landuseChildren,
        "expected staged landuse folder child count to match whole chunk import"
    )
    Assert.equal(
        stagedSnapshot.barriersChildren,
        fullSnapshot.barriersChildren,
        "expected staged barrier folder child count to match whole chunk import"
    )
    Assert.equal(
        stagedSnapshot.waterChildren,
        fullSnapshot.waterChildren,
        "expected staged water folder child count to match whole chunk import"
    )
    Assert.equal(
        stagedSnapshot.propsChildren,
        fullSnapshot.propsChildren,
        "expected staged props folder child count to match whole chunk import"
    )
    Assert.equal(
        stagedSnapshot.descendantCounts.parts,
        fullSnapshot.descendantCounts.parts,
        "expected staged part count to match whole chunk import"
    )
    Assert.equal(
        stagedSnapshot.descendantCounts.models,
        fullSnapshot.descendantCounts.models,
        "expected staged model count to match whole chunk import"
    )

    Workspace:FindFirstChild(fullWorldRootName):Destroy()
    Workspace:FindFirstChild(stagedWorldRootName):Destroy()
    ImportService.ResetSubplanState(chunk.id)
end

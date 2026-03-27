return function()
    local Workspace = game:GetService("Workspace")
    local ImportService = require(script.Parent.Parent.ImportService)
    local Assert = require(script.Parent.Assert)

    local manifest = {
        schemaVersion = "0.4.0",
        meta = {
            worldName = "RoofOnlyRooftopAttachmentTruth",
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
                        id = "roof_penthouse_cap",
                        footprint = {
                            { x = 0, z = 0 },
                            { x = 12, z = 0 },
                            { x = 12, z = 12 },
                            { x = 0, z = 12 },
                            { x = 0, z = 0 },
                        },
                        baseY = 20,
                        minHeight = 20,
                        height = 3,
                        roof = "flat",
                        usage = "roof",
                        material = "Concrete",
                    },
                    {
                        id = "roof_legacy_top_height",
                        footprint = {
                            { x = 20, z = 0 },
                            { x = 32, z = 0 },
                            { x = 32, z = 12 },
                            { x = 20, z = 12 },
                            { x = 20, z = 0 },
                        },
                        baseY = 0,
                        minHeight = 0,
                        height = 40,
                        roof = "flat",
                        usage = "roof",
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

    local worldRootName = "GeneratedWorld_RoofOnlyRooftopAttachmentTruth"
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
    Assert.truthy(worldRoot, "expected rooftop roof-only structure world root")

    local canopy = worldRoot:FindFirstChild("0_0"):FindFirstChild("Buildings"):FindFirstChild("roof_penthouse_cap")
    Assert.truthy(canopy, "expected rooftop roof-only structure model")

    local roofParts = {}
    local supportPosts = {}
    for _, descendant in ipairs(canopy:GetDescendants()) do
        if descendant:IsA("BasePart") then
            if string.find(descendant.Name, "_roof", 1, true) then
                roofParts[#roofParts + 1] = descendant
            elseif descendant.Name == "SupportPost" then
                supportPosts[#supportPosts + 1] = descendant
            end
        end
    end

    Assert.truthy(#roofParts >= 1, "expected rooftop roof-only structure to keep roof geometry")
    Assert.equal(#supportPosts, 0, "expected rooftop roof-only structures to avoid canopy-style support posts")

    local legacyRoof =
        worldRoot:FindFirstChild("0_0"):FindFirstChild("Buildings"):FindFirstChild("roof_legacy_top_height")
    Assert.truthy(legacyRoof, "expected stale roof-only legacy structure model")

    local legacyRoofParts = {}
    local legacySupportPosts = {}
    for _, descendant in ipairs(legacyRoof:GetDescendants()) do
        if descendant:IsA("BasePart") then
            if string.find(descendant.Name, "_roof", 1, true) then
                legacyRoofParts[#legacyRoofParts + 1] = descendant
            elseif descendant.Name == "SupportPost" then
                legacySupportPosts[#legacySupportPosts + 1] = descendant
            end
        end
    end

    Assert.truthy(#legacyRoofParts >= 1, "expected legacy roof-only structure to keep roof geometry")
    Assert.equal(
        #legacySupportPosts,
        0,
        "expected legacy roof-only top-height structures to normalize as rooftop attachments"
    )
    local legacyBaseY = legacyRoof:GetAttribute("ArnisImportBuildingBaseY")
    local legacyHeight = legacyRoof:GetAttribute("ArnisImportBuildingHeight")
    Assert.truthy(type(legacyBaseY) == "number" and legacyBaseY >= 36.5, "expected legacy roof base to be lifted")
    Assert.truthy(
        type(legacyHeight) == "number" and legacyHeight <= 4.5,
        "expected legacy roof height to be normalized"
    )

    worldRoot:Destroy()
end

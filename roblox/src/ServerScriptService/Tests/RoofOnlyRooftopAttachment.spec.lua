return function()
    local Workspace = game:GetService("Workspace")
    local ImportService = require(script.Parent.Parent.ImportService)
    local Assert = require(script.Parent.Assert)

    local manifest = {
        schemaVersion = "0.4.0",
        meta = {
            worldName = "RoofOnlyRooftopAttachment",
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
                        id = "rooftop_canopy",
                        footprint = {
                            { x = 0, z = 0 },
                            { x = 20, z = 0 },
                            { x = 20, z = 12 },
                            { x = 0, z = 12 },
                            { x = 0, z = 0 },
                        },
                        baseY = 0,
                        minHeight = 12,
                        height = 16,
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

    local worldRootName = "GeneratedWorld_RoofOnlyRooftopAttachment"
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
    Assert.truthy(worldRoot, "expected roof-only rooftop attachment world root")

    local canopy = worldRoot
        :FindFirstChild("0_0")
        :FindFirstChild("Buildings")
        :FindFirstChild("rooftop_canopy")
    Assert.truthy(canopy, "expected roof-only rooftop canopy model")

    local supportPosts = {}
    local roofParts = {}
    for _, descendant in ipairs(canopy:GetDescendants()) do
        if descendant:IsA("BasePart") then
            if descendant.Name == "SupportPost" then
                supportPosts[#supportPosts + 1] = descendant
            elseif string.find(descendant.Name, "_roof", 1, true) then
                roofParts[#roofParts + 1] = descendant
            end
        end
    end

    Assert.equal(#supportPosts, 4, "expected rectangular rooftop canopy to emit four support posts")
    Assert.truthy(#roofParts >= 1, "expected rooftop canopy to keep direct roof geometry")

    for _, supportPost in ipairs(supportPosts) do
        local supportTopY = supportPost.Position.Y + supportPost.Size.Y * 0.5
        Assert.near(
            supportTopY,
            manifest.chunks[1].buildings[1].minHeight,
            0.05,
            "expected roof-only supports to terminate at the known rooftop base instead of full roof height"
        )
    end

    worldRoot:Destroy()
end

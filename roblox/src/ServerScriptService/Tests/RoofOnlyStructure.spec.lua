return function()
    local Workspace = game:GetService("Workspace")
    local ImportService = require(script.Parent.Parent.ImportService)
    local Assert = require(script.Parent.Assert)

    local manifest = {
        schemaVersion = "0.4.0",
        meta = {
            worldName = "RoofOnlyStructureTruth",
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
                        id = "gas_station_canopy",
                        footprint = {
                            { x = 0, z = 0 },
                            { x = 24, z = 0 },
                            { x = 24, z = 16 },
                            { x = 0, z = 16 },
                            { x = 0, z = 0 },
                        },
                        baseY = 0,
                        height = 6,
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

    local worldRootName = "GeneratedWorld_RoofOnlyStructureTruth"
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
    Assert.truthy(worldRoot, "expected roof-only structure world root")

    local canopy = worldRoot
        :FindFirstChild("0_0")
        :FindFirstChild("Buildings")
        :FindFirstChild("gas_station_canopy")
    Assert.truthy(canopy, "expected roof-only structure model")

    local shellFolder = canopy:FindFirstChild("Shell")
    Assert.truthy(shellFolder, "expected dedicated shell folder for roof-only structure")

    local roofParts = {}
    local supportPosts = {}
    local wallParts = {}
    for _, descendant in ipairs(canopy:GetDescendants()) do
        if descendant:IsA("BasePart") then
            if string.find(descendant.Name, "_roof", 1, true) then
                roofParts[#roofParts + 1] = descendant
            elseif descendant.Name == "SupportPost" then
                supportPosts[#supportPosts + 1] = descendant
            elseif string.find(descendant.Name, "_wall", 1, true) then
                wallParts[#wallParts + 1] = descendant
            end
        end
    end

    Assert.truthy(#roofParts >= 1, "expected roof-only structure to keep its roof geometry")
    Assert.equal(
        #supportPosts,
        4,
        "expected rectangular roof-only structure to emit four support posts"
    )
    Assert.equal(#wallParts, 0, "expected roof-only structures to avoid perimeter wall shells")

    worldRoot:Destroy()
end

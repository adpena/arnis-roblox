return function()
    local Workspace = game:GetService("Workspace")
    local ImportService = require(script.Parent.Parent.ImportService)
    local GroundSampler = require(script.Parent.Parent.ImportService.GroundSampler)
    local WaterBuilder = require(script.Parent.Parent.ImportService.Builders.WaterBuilder)
    local Assert = require(script.Parent.Assert)

    local originalCreateSampler = GroundSampler.createSampler
    local samplerCalls = 0

    GroundSampler.createSampler = function(chunk)
        samplerCalls += 1
        return originalCreateSampler(chunk)
    end

    local ok, err = pcall(function()
        local manifest = {
            schemaVersion = "0.2.0",
            meta = {
                worldName = "SamplerReuse",
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
                        heights = table.create(16 * 16, 0),
                        material = "Grass",
                    },
                    roads = {},
                    rails = {},
                    buildings = {
                        {
                            id = "b1",
                            footprint = { { x = 0, z = 0 }, { x = 16, z = 0 }, { x = 16, z = 16 }, { x = 0, z = 16 } },
                            baseY = 0,
                            height = 12,
                            roof = "flat",
                            material = "Concrete",
                        },
                        {
                            id = "b2",
                            footprint = { { x = 24, z = 0 }, { x = 40, z = 0 }, { x = 40, z = 16 }, { x = 24, z = 16 } },
                            baseY = 0,
                            height = 12,
                            roof = "flat",
                            material = "Concrete",
                        },
                    },
                    water = {
                        {
                            id = "w1",
                            kind = "pond",
                            material = "Water",
                            footprint = { { x = 0, z = 24 }, { x = 16, z = 24 }, { x = 16, z = 40 }, { x = 0, z = 40 } },
                            holes = {},
                        },
                        {
                            id = "w2",
                            kind = "pond",
                            material = "Water",
                            footprint = {
                                { x = 24, z = 24 },
                                { x = 40, z = 24 },
                                { x = 40, z = 40 },
                                { x = 24, z = 40 },
                            },
                            holes = {},
                        },
                    },
                    props = {},
                    landuse = {},
                    barriers = {},
                },
            },
        }

        local chunk = manifest.chunks[1]
        local directParent = Instance.new("Folder")
        directParent.Name = "DirectWaterSamplerReuse"
        directParent.Parent = Workspace
        WaterBuilder.BuildAll(directParent, chunk.water, chunk.originStuds, chunk)
        Assert.equal(samplerCalls, 1, "expected direct WaterBuilder.BuildAll to reuse one sampler for the layer")
        directParent:Destroy()

        ImportService.ImportManifest(manifest, {
            clearFirst = true,
            worldRootName = "GeneratedWorld_SamplerReuse",
            config = {
                BuildingMode = "shellMesh",
                TerrainMode = "none",
                RoadMode = "none",
                WaterMode = "mesh",
                LanduseMode = "none",
            },
        })

        Assert.equal(
            samplerCalls,
            3,
            "expected one sampler for direct water build and one per imported buildings/water layer"
        )

        local worldRoot = Workspace:FindFirstChild("GeneratedWorld_SamplerReuse")
        if worldRoot then
            worldRoot:Destroy()
        end
    end)

    GroundSampler.createSampler = originalCreateSampler

    if not ok then
        error(err)
    end
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ChunkSchema = require(ReplicatedStorage.Shared.ChunkSchema)
local ManifestLoader = require(script.Parent.Parent.ImportService.ManifestLoader)
local Assert = require(script.Parent.Assert)

return function()
    local manifest = ManifestLoader.LoadNamedSample("SampleManifest")
    local validated = ChunkSchema.validateManifest(manifest)
    Assert.equal(validated.schemaVersion, "0.4.0", "expected current schema version")
    Assert.equal(#validated.chunks, 1, "expected one sample chunk")

    local oldManifest = {
        schemaVersion = "0.1.0",
        meta = {
            worldName = "Test",
            generator = "test",
            source = "test",
            metersPerStud = 1,
            chunkSizeStuds = 256,
            bbox = { minLat = 0, minLon = 0, maxLat = 1, maxLon = 1 },
        },
        chunks = {
            {
                id = "0_0",
                originStuds = { x = 0, y = 0, z = 0 },
                roads = {},
                rails = {},
                buildings = {},
                water = {},
                props = {},
            },
        },
    }
    local migrated = ChunkSchema.validateManifest(oldManifest)
    Assert.equal(migrated.schemaVersion, "0.4.0", "expected migrated schema version")
    Assert.equal(migrated.meta.totalFeatures, 0, "expected migrated totalFeatures")
    Assert.equal(#migrated.chunks[1].landuse, 0, "expected migrated empty landuse")
    Assert.equal(#migrated.chunks[1].barriers, 0, "expected migrated empty barriers")

    local badManifest = {
        schemaVersion = "0.4.0",
        meta = {
            worldName = "Test",
            generator = "test",
            source = "test",
            metersPerStud = 0.3,
            chunkSizeStuds = 256,
            bbox = { minLat = 0, minLon = 0, maxLat = 1, maxLon = 1 },
            totalFeatures = 0,
        },
        chunks = {},
    }
    local ok = pcall(function()
        ChunkSchema.validateManifest(badManifest)
    end)
    Assert.falsy(ok, "expected empty chunk list to fail validation")
end

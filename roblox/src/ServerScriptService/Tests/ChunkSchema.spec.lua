local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local TestEZ = require(ReplicatedStorage.Testing.TestEZ)
local ChunkSchema = require(ReplicatedStorage.Shared.ChunkSchema)

return function()
    TestEZ.describe("ChunkSchema", function()
        TestEZ.describe("validateManifest", function()
            TestEZ.it("should accept valid 0.2.0 manifest", function()
                local manifest = require(ServerStorage.SampleData.SampleManifest)
                local validated = ChunkSchema.validateManifest(manifest)
                TestEZ.expect(validated.schemaVersion).toEqual("0.2.0")
                TestEZ.expect(#validated.chunks).toEqual(1)
            end)

            TestEZ.it("should migrate 0.1.0 to 0.2.0", function()
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
                        }
                    }
                }
                local validated = ChunkSchema.validateManifest(oldManifest)
                TestEZ.expect(validated.schemaVersion).toEqual("0.2.0")
                TestEZ.expect(validated.meta.totalFeatures).toEqual(0)
            end)

            TestEZ.it("should reject manifest without chunks", function()
                local badManifest = {
                    schemaVersion = "0.2.0",
                    meta = {
                        worldName = "Test",
                        generator = "test",
                        source = "test",
                        metersPerStud = 1,
                        chunkSizeStuds = 256,
                        bbox = { minLat = 0, minLon = 0, maxLat = 1, maxLon = 1 },
                        totalFeatures = 0,
                    },
                    chunks = {}
                }
                local ok, _ = pcall(function()
                    ChunkSchema.validateManifest(badManifest)
                end)
                TestEZ.expect(ok).toBeFalse()
            end)
        end)
    end)
end

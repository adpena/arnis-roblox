local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TestEZ = require(ReplicatedStorage.Testing.TestEZ)
local Migrations = require(ReplicatedStorage.Shared.Migrations)

return function()
    TestEZ.describe("Migrations", function()
        TestEZ.describe("migrate", function()
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
                            roads = { { id = "r1" } },
                            rails = {},
                            buildings = { { id = "b1" } },
                            water = {},
                            props = {},
                        }
                    }
                }

                local migrated = Migrations.migrate(oldManifest, "0.2.0")
                TestEZ.expect(migrated.schemaVersion).toEqual("0.2.0")
                TestEZ.expect(migrated.meta.totalFeatures).toEqual(2)
            end)

            TestEZ.it("should return same version if already at target", function()
                local manifest = {
                    schemaVersion = "0.2.0",
                    meta = { totalFeatures = 5 },
                    chunks = {}
                }
                local result = Migrations.migrate(manifest, "0.2.0")
                TestEZ.expect(result.schemaVersion).toEqual("0.2.0")
            end)
        end)
    end)
end
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Migrations = require(ReplicatedStorage.Shared.Migrations)
local Assert = require(script.Parent.Assert)

return function()
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
            },
        },
    }

    local migrated = Migrations.migrate(oldManifest, "0.4.0")
    Assert.equal(migrated.schemaVersion, "0.4.0", "expected migrated schema version")
    Assert.equal(migrated.meta.totalFeatures, 2, "expected migrated totalFeatures")
    Assert.equal(
        migrated.chunks[1].roads[1].hasSidewalk,
        false,
        "expected migrated sidewalk default"
    )
    Assert.equal(migrated.chunks[1].roads[1].elevated, false, "expected migrated elevated default")
    Assert.equal(migrated.chunks[1].roads[1].tunnel, false, "expected migrated tunnel default")
    Assert.equal(#migrated.chunks[1].landuse, 0, "expected migrated empty landuse")
    Assert.equal(#migrated.chunks[1].barriers, 0, "expected migrated empty barriers")

    -- 0.3.0 → 0.4.0: scale factor, renamed fields, new defaults
    local manifest030 = {
        schemaVersion = "0.3.0",
        meta = {
            worldName = "Test030",
            generator = "test",
            source = "test",
            metersPerStud = 1.0,
            chunkSizeStuds = 256,
            bbox = { minLat = 0, minLon = 0, maxLat = 1, maxLon = 1 },
            totalFeatures = 2,
        },
        chunks = {
            {
                id = "0_0",
                originStuds = { x = 0, y = 0, z = 0 },
                roads = {
                    {
                        id = "r1",
                        kind = "primary",
                        material = "Asphalt",
                        widthStuds = 10,
                        hasSidewalk = true,
                        points = {
                            { x = 0, y = 0, z = 0 },
                            { x = 30, y = 0, z = 0 },
                        },
                    },
                },
                rails = {},
                buildings = {
                    {
                        id = "b1",
                        kind = "default",
                        material = "Concrete",
                        color = { r = 200, g = 180, b = 150 },
                        footprint = {
                            { x = 0, z = 0 },
                            { x = 30, z = 0 },
                            { x = 30, z = 30 },
                            { x = 0, z = 30 },
                        },
                        baseY = 0,
                        height = 12,
                        height_m = 10,
                        levels = 3,
                        roofLevels = 0,
                        roof = "flat",
                        rooms = {},
                    },
                },
                water = {},
                props = {},
                landuse = {},
                barriers = {},
            },
        },
    }
    local scale = 1.0 / 0.3
    local result040 = Migrations.migrate(manifest030, "0.4.0")
    Assert.equal(result040.schemaVersion, "0.4.0", "expected 0.4.0 schema version")
    Assert.equal(result040.meta.metersPerStud, 0.3, "expected metersPerStud 0.3")
    Assert.near(result040.meta.chunkSizeStuds, 256 * scale, 0.01, "expected scaled chunkSizeStuds")
    -- road points scaled; widthStuds scaled
    Assert.near(
        result040.chunks[1].roads[1].points[2].x,
        30 * scale,
        0.01,
        "expected scaled road point x"
    )
    Assert.near(
        result040.chunks[1].roads[1].widthStuds,
        10 * scale,
        0.01,
        "expected scaled road widthStuds"
    )
    Assert.equal(result040.chunks[1].roads[1].elevated, false, "expected elevated default")
    Assert.equal(result040.chunks[1].roads[1].tunnel, false, "expected tunnel default")
    -- building: height scaled, height_m and levels NOT scaled
    Assert.near(
        result040.chunks[1].buildings[1].height,
        12 * scale,
        0.01,
        "expected scaled building height"
    )
    Assert.equal(result040.chunks[1].buildings[1].height_m, 10, "expected height_m unchanged")
    Assert.equal(result040.chunks[1].buildings[1].levels, 3, "expected levels unchanged")
    -- color renamed to wallColor
    Assert.equal(
        result040.chunks[1].buildings[1].wallColor ~= nil,
        true,
        "expected wallColor present"
    )
    Assert.equal(result040.chunks[1].buildings[1].color, nil, "expected color removed")

    local manifest020LegacyWater = {
        schemaVersion = "0.2.0",
        meta = {
            worldName = "LegacyWater",
            generator = "test",
            source = "test",
            metersPerStud = 1.0,
            chunkSizeStuds = 256,
            bbox = { minLat = 0, minLon = 0, maxLat = 1, maxLon = 1 },
            totalFeatures = 2,
        },
        chunks = {
            {
                id = "0_0",
                originStuds = { x = 0, y = 0, z = 0 },
                roads = {},
                rails = {},
                buildings = {},
                water = {
                    {
                        id = "river_1",
                        points = {
                            { x = 0, y = 4, z = 0 },
                            { x = 16, y = 4, z = 0 },
                        },
                        widthStuds = 8,
                    },
                    {
                        id = "lake_1",
                        footprint = {
                            { x = 0, z = 0 },
                            { x = 16, z = 0 },
                            { x = 16, z = 16 },
                        },
                    },
                },
                props = {},
                landuse = {},
                barriers = {},
            },
        },
    }

    local migratedLegacyWater = Migrations.migrate(manifest020LegacyWater, "0.4.0")
    Assert.equal(
        migratedLegacyWater.schemaVersion,
        "0.4.0",
        "expected migrated legacy water schema version"
    )
    Assert.equal(
        migratedLegacyWater.chunks[1].water[1].kind,
        "river",
        "expected ribbon water fallback kind"
    )
    Assert.equal(
        migratedLegacyWater.chunks[1].water[1].material,
        "Water",
        "expected ribbon water fallback material"
    )
    Assert.equal(
        migratedLegacyWater.chunks[1].water[2].kind,
        "lake",
        "expected polygon water fallback kind"
    )
    Assert.equal(
        migratedLegacyWater.chunks[1].water[2].material,
        "Water",
        "expected polygon water fallback material"
    )
    Assert.equal(
        #migratedLegacyWater.chunks[1].water[2].holes,
        0,
        "expected polygon water fallback holes"
    )

    local manifest = {
        schemaVersion = "0.4.0",
        meta = { totalFeatures = 5 },
        chunks = {},
    }
    local result = Migrations.migrate(manifest, "0.4.0")
    Assert.equal(result.schemaVersion, "0.4.0", "expected unchanged schema version")
end

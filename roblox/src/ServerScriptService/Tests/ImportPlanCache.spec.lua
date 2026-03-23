return function()
    local ImportPlanCache = require(script.Parent.Parent.ImportService.ImportPlanCache)
    local Assert = require(script.Parent.Assert)

    ImportPlanCache.Clear()
    local baselineStats = ImportPlanCache.GetStats()

    local chunk = {
        id = "0_0",
        originStuds = { x = 0, y = 0, z = 0 },
        terrain = {
            cellSizeStuds = 16,
            width = 2,
            depth = 2,
            heights = { 0, 0, 0, 0 },
            material = "Grass",
        },
        roads = {
            {
                id = "road_1",
                points = {
                    { x = 0, y = 0, z = 0 },
                    { x = 10, y = 0, z = 0 },
                },
            },
        },
        rails = {},
        buildings = {
            {
                id = "building_1",
                footprint = {
                    { x = 0, z = 0 },
                    { x = 10, z = 0 },
                    { x = 10, z = 10 },
                },
            },
        },
        water = {},
        props = {},
        landuse = {
            {
                id = "park_1",
                kind = "park",
                footprint = {
                    { x = 0, z = 0 },
                    { x = 16, z = 0 },
                    { x = 16, z = 16 },
                    { x = 0, z = 16 },
                },
            },
        },
        barriers = {},
    }

    local config = {
        TerrainMode = "paint",
        RoadMode = "mesh",
        BuildingMode = "shellMesh",
        WaterMode = "mesh",
        LanduseMode = "terrain",
    }

    ImportPlanCache.Clear()

    local firstPlan = ImportPlanCache.GetOrCreatePlan(chunk, {
        config = config,
        configSignature = "cfg-high",
        layerSignatures = {
            terrain = "paint",
            roads = "mesh",
            buildings = "shellMesh",
            water = "mesh",
            props = "default",
            landuse = "terrain",
            barriers = "default",
        },
    })
    local secondPlan = ImportPlanCache.GetOrCreatePlan(chunk, {
        config = config,
        configSignature = "cfg-high",
        layerSignatures = {
            terrain = "paint",
            roads = "mesh",
            buildings = "shellMesh",
            water = "mesh",
            props = "default",
            landuse = "terrain",
            barriers = "default",
        },
    })

    Assert.equal(
        firstPlan,
        secondPlan,
        "expected identical chunk/config inputs to reuse cached plan table"
    )
    Assert.truthy(
        firstPlan.actions and #firstPlan.actions > 0,
        "expected cached plan to include executable actions"
    )
    Assert.truthy(firstPlan.folderSpecs.roads, "expected cached plan to prepare roads folder")
    Assert.truthy(
        firstPlan.folderSpecs.buildings,
        "expected cached plan to prepare buildings folder"
    )
    Assert.truthy(firstPlan.prepared, "expected cached plan to include prepared subplans")
    Assert.truthy(firstPlan.prepared.terrain, "expected prepared terrain subplan")
    Assert.truthy(firstPlan.prepared.roads, "expected prepared road subplan")
    Assert.truthy(firstPlan.prepared.landuse, "expected prepared landuse subplan")
    Assert.equal(
        firstPlan.prepared.terrain,
        secondPlan.prepared.terrain,
        "expected terrain subplan reuse"
    )
    Assert.equal(firstPlan.prepared.roads, secondPlan.prepared.roads, "expected road subplan reuse")
    Assert.equal(
        firstPlan.prepared.landuse,
        secondPlan.prepared.landuse,
        "expected landuse subplan reuse"
    )

    local cacheStats = ImportPlanCache.GetStats()
    Assert.equal(
        cacheStats.misses - baselineStats.misses,
        1,
        "expected first plan lookup to miss once"
    )
    Assert.equal(
        cacheStats.hits - baselineStats.hits,
        1,
        "expected second identical plan lookup to hit cache once"
    )
    Assert.equal(cacheStats.size, 1, "expected one cached plan entry after identical lookups")

    local selectivePlan = ImportPlanCache.GetOrCreatePlan(chunk, {
        config = config,
        configSignature = "cfg-high",
        layerSignatures = {
            terrain = "paint",
            roads = "mesh",
            buildings = "shellMesh",
            water = "mesh",
            props = "default",
            landuse = "terrain",
            barriers = "default",
        },
        layers = {
            roads = true,
        },
    })

    Assert.falsy(
        selectivePlan == firstPlan,
        "expected selective layer plan to have a distinct cache entry"
    )
    Assert.truthy(
        selectivePlan.folderSpecs.roads,
        "expected selective plan to keep requested roads folder"
    )
    Assert.falsy(
        selectivePlan.folderSpecs.buildings,
        "expected selective plan to omit unrelated buildings folder"
    )
    Assert.truthy(
        selectivePlan.prepared.roads,
        "expected selective road plan to keep prepared road subplan"
    )
    Assert.falsy(
        selectivePlan.prepared.landuse,
        "expected selective road plan to omit landuse subplan"
    )

    cacheStats = ImportPlanCache.GetStats()
    Assert.equal(
        cacheStats.misses - baselineStats.misses,
        2,
        "expected selective plan to create a second cache entry"
    )
    Assert.equal(cacheStats.size, 2, "expected selective plan to be cached separately")

    local semanticSiblingChunk = {
        id = "0_0",
        originStuds = { x = 0, y = 0, z = 0 },
        terrain = chunk.terrain,
        roads = {
            {
                id = "road_1",
                kind = "secondary",
                hasSidewalk = true,
                points = {
                    { x = 0, y = 0, z = 0 },
                    { x = 10, y = 0, z = 0 },
                },
            },
        },
        rails = {},
        buildings = chunk.buildings,
        water = {},
        props = {},
        landuse = chunk.landuse,
        barriers = {},
    }

    local semanticSiblingPlan = ImportPlanCache.GetOrCreatePlan(semanticSiblingChunk, {
        config = config,
        configSignature = "cfg-high",
        layerSignatures = {
            terrain = "paint",
            roads = "mesh",
            buildings = "shellMesh",
            water = "mesh",
            props = "default",
            landuse = "terrain",
            barriers = "default",
        },
    })

    Assert.falsy(
        semanticSiblingPlan == firstPlan,
        "expected distinct chunk tables with different road semantics to avoid stale plan reuse"
    )
    Assert.falsy(
        semanticSiblingPlan.prepared.roads == firstPlan.prepared.roads,
        "expected prepared road plan identity to differ for semantic sibling chunk"
    )

    cacheStats = ImportPlanCache.GetStats()
    Assert.equal(
        cacheStats.misses - baselineStats.misses,
        3,
        "expected semantic sibling chunk to create a third cache miss"
    )
    Assert.equal(
        cacheStats.size,
        3,
        "expected semantic sibling chunk to occupy its own cache entry"
    )
end

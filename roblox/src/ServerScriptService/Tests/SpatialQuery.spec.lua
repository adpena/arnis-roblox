return function()
    local SpatialQuery = require(script.Parent.Parent.ImportService.SpatialQuery)
    local Assert = require(script.Parent.Assert)

    local roads = {
        {
            id = "road_1",
            kind = "primary",
            widthStuds = 12,
            hasSidewalk = true,
            points = {
                { x = 0, y = 0, z = 20 },
                { x = 120, y = 0, z = 20 },
            },
        },
    }
    local originStuds = { x = 100, y = 0, z = 200 }

    local nearRoad, nearMatch = SpatialQuery.isPointNearAnyRoad(roads, originStuds, 160, 223)
    Assert.truthy(nearRoad, "expected point near road corridor")
    Assert.truthy(nearMatch, "expected near-road query result")
    Assert.equal(nearMatch.road.id, "road_1", "expected matching road")

    local farRoad = SpatialQuery.isPointNearAnyRoad(roads, originStuds, 160, 245)
    Assert.falsy(farRoad, "expected point outside road corridor")

    local nearest = SpatialQuery.findNearestRoadSegment(roads, originStuds, 160, 223)
    Assert.truthy(nearest, "expected nearest road segment")
    Assert.equal(nearest.road.id, "road_1", "expected nearest road segment id")
    Assert.near(nearest.projX, 160, 0.001, "expected projection along road")
    Assert.near(nearest.projZ, 220, 0.001, "expected projected road centerline")
end

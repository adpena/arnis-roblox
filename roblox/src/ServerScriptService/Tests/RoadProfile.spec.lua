return function()
    local RoadProfile = require(script.Parent.Parent.ImportService.RoadProfile)
    local Assert = require(script.Parent.Assert)

    local primaryWithSidewalk = {
        kind = "primary",
        widthStuds = 20,
        lanes = 2,
        hasSidewalk = true,
    }
    local residentialNoSidewalk = {
        kind = "residential",
        widthStuds = 8,
        hasSidewalk = false,
    }

    Assert.equal(
        RoadProfile.getRoadWidth(primaryWithSidewalk),
        20,
        "expected explicit manifest width to stay authoritative even when lanes metadata exists"
    )
    Assert.near(
        RoadProfile.getSidewalkWidth(primaryWithSidewalk, 20),
        4,
        0.001,
        "expected sidewalk width to be derived from the canonical road width"
    )
    Assert.truthy(
        RoadProfile.getRoadClearance(primaryWithSidewalk, 20) > 12,
        "expected wider road clearance when sidewalks exist"
    )

    Assert.equal(
        RoadProfile.getSidewalkWidth(residentialNoSidewalk, 8),
        0,
        "expected no sidewalk width when flag is false"
    )
    Assert.truthy(
        RoadProfile.getEdgeBufferWidth(residentialNoSidewalk, 8) > 0,
        "expected edge buffer even without sidewalks"
    )
end

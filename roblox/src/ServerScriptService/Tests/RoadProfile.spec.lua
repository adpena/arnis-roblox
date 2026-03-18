return function()
    local RoadProfile = require(script.Parent.Parent.ImportService.RoadProfile)
    local Assert = require(script.Parent.Assert)

    local primaryWithSidewalk = {
        kind = "primary",
        widthStuds = 12,
        hasSidewalk = true,
    }
    local residentialNoSidewalk = {
        kind = "residential",
        widthStuds = 8,
        hasSidewalk = false,
    }

    Assert.equal(RoadProfile.getRoadWidth(primaryWithSidewalk), 12, "expected explicit road width")
    Assert.near(
        RoadProfile.getSidewalkWidth(primaryWithSidewalk, 12),
        3,
        0.001,
        "expected sidewalk width from road profile"
    )
    Assert.truthy(
        RoadProfile.getRoadClearance(primaryWithSidewalk, 12) > 9,
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

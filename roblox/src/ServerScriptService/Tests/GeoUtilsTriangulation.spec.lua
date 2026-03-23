return function()
    local GeoUtils = require(script.Parent.Parent.ImportService.GeoUtils)
    local Assert = require(script.Parent.Assert)

    local function signedArea(poly)
        local area = 0
        for i = 1, #poly do
            local p1 = poly[i]
            local p2 = poly[(i % #poly) + 1]
            area += (p1.x * p2.z) - (p2.x * p1.z)
        end
        return area * 0.5
    end

    local function triangleArea(a, b, c)
        return math.abs(((a.x * (b.z - c.z)) + (b.x * (c.z - a.z)) + (c.x * (a.z - b.z))) * 0.5)
    end

    local function pointInTriangle(px, pz, a, b, c)
        local function sign(p1x, p1z, p2, p3)
            return (p1x - p3.x) * (p2.z - p3.z) - (p2.x - p3.x) * (p1z - p3.z)
        end

        local d1 = sign(px, pz, a, b)
        local d2 = sign(px, pz, b, c)
        local d3 = sign(px, pz, c, a)
        local hasNeg = d1 < 0 or d2 < 0 or d3 < 0
        local hasPos = d1 > 0 or d2 > 0 or d3 > 0
        return not (hasNeg and hasPos)
    end

    local indexedFootprint = {
        { x = 0, z = 0 },
        { x = 4, z = 0 },
        { x = 4, z = 4 },
        { x = 0, z = 4 },
    }
    local indexedTriangles = GeoUtils.triangulatePolygon(indexedFootprint, { 0, 1, 2, 0, 2, 3 })
    Assert.equal(
        #indexedTriangles,
        2,
        "expected explicit triangle indices to produce two triangles"
    )
    Assert.equal(
        indexedTriangles[1][1],
        1,
        "expected 0-based manifest indices to map to Luau 1-based triangle indices"
    )
    Assert.equal(indexedTriangles[1][2], 2, "expected second explicit index")
    Assert.equal(indexedTriangles[1][3], 3, "expected third explicit index")
    Assert.equal(indexedTriangles[2][1], 1, "expected second triangle first index")
    Assert.equal(indexedTriangles[2][2], 3, "expected second triangle second index")
    Assert.equal(indexedTriangles[2][3], 4, "expected second triangle third index")

    local closedQuad = {
        { x = 0, z = 0 },
        { x = 4, z = 0 },
        { x = 4, z = 4 },
        { x = 0, z = 4 },
        { x = 0, z = 0 },
    }
    local closedQuadTriangles =
        GeoUtils.triangulatePolygon(closedQuad, { 1, 2, 3, 1, 3, 4, 0, 1, 4 })
    Assert.equal(
        #closedQuadTriangles,
        2,
        "expected duplicate-closing-vertex indices to collapse into a valid quad"
    )
    local closedQuadArea = 0
    for _, tri in ipairs(closedQuadTriangles) do
        closedQuadArea += triangleArea(closedQuad[tri[1]], closedQuad[tri[2]], closedQuad[tri[3]])
        Assert.truthy(
            tri[1] <= 4 and tri[2] <= 4 and tri[3] <= 4,
            "expected triangulation to ignore the duplicated closing vertex"
        )
    end
    Assert.near(
        closedQuadArea,
        16,
        1e-6,
        "expected duplicate closing vertex triangulation to preserve full roof area"
    )

    local malformedExplicitFootprint = {
        { x = 0, z = 0 },
        { x = 8, z = 0 },
        { x = 12, z = 4 },
        { x = 12, z = 12 },
        { x = 4, z = 12 },
        { x = 0, z = 8 },
        { x = 0, z = 0 },
    }
    local repairedTriangles = GeoUtils.triangulatePolygon(malformedExplicitFootprint, { 2, 3, 4 })
    Assert.truthy(
        #repairedTriangles >= 4,
        "expected malformed explicit indices to be rejected and replaced by fallback triangulation"
    )
    local repairedArea = 0
    for _, tri in ipairs(repairedTriangles) do
        repairedArea += triangleArea(
            malformedExplicitFootprint[tri[1]],
            malformedExplicitFootprint[tri[2]],
            malformedExplicitFootprint[tri[3]]
        )
    end
    Assert.near(
        repairedArea,
        math.abs(signedArea({
            malformedExplicitFootprint[1],
            malformedExplicitFootprint[2],
            malformedExplicitFootprint[3],
            malformedExplicitFootprint[4],
            malformedExplicitFootprint[5],
            malformedExplicitFootprint[6],
        })),
        1e-6,
        "expected fallback triangulation to cover the full simplified footprint area"
    )

    local concaveFootprint = {
        { x = 0, z = 0 },
        { x = 32, z = 0 },
        { x = 32, z = 16 },
        { x = 16, z = 16 },
        { x = 16, z = 32 },
        { x = 0, z = 32 },
    }
    local concaveTriangles = GeoUtils.triangulatePolygon(concaveFootprint)
    Assert.truthy(
        #concaveTriangles >= 4,
        "expected concave polygon to triangulate into multiple triangles"
    )

    local totalArea = 0
    for _, tri in ipairs(concaveTriangles) do
        totalArea += triangleArea(
            concaveFootprint[tri[1]],
            concaveFootprint[tri[2]],
            concaveFootprint[tri[3]]
        )
    end
    Assert.near(
        totalArea,
        math.abs(signedArea(concaveFootprint)),
        1e-6,
        "expected triangulation area to match polygon area"
    )

    local emptyCornerCovered = false
    for _, tri in ipairs(concaveTriangles) do
        if
            pointInTriangle(
                24,
                24,
                concaveFootprint[tri[1]],
                concaveFootprint[tri[2]],
                concaveFootprint[tri[3]]
            )
        then
            emptyCornerCovered = true
            break
        end
    end
    Assert.falsy(
        emptyCornerCovered,
        "expected concave triangulation to leave the empty L-shape corner uncovered"
    )
end

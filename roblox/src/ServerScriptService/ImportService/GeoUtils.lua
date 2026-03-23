local GeoUtils = {}
local POINT_EPSILON = 1e-4

local function signedArea(poly)
    local area = 0
    for i = 1, #poly do
        local p1 = poly[i]
        local p2 = poly[(i % #poly) + 1]
        area += (p1.x * p2.z) - (p2.x * p1.z)
    end
    return area * 0.5
end

local function orient2d(a, b, c)
    return ((b.x - a.x) * (c.z - a.z)) - ((b.z - a.z) * (c.x - a.x))
end

local function pointInTriangle(px, pz, a, b, c)
    local d1 = ((px - b.x) * (a.z - b.z)) - ((a.x - b.x) * (pz - b.z))
    local d2 = ((px - c.x) * (b.z - c.z)) - ((b.x - c.x) * (pz - c.z))
    local d3 = ((px - a.x) * (c.z - a.z)) - ((c.x - a.x) * (pz - a.z))
    local hasNeg = d1 < 0 or d2 < 0 or d3 < 0
    local hasPos = d1 > 0 or d2 > 0 or d3 > 0
    return not (hasNeg and hasPos)
end

local function pointsEqual2d(a, b)
    return math.abs(a.x - b.x) <= POINT_EPSILON and math.abs(a.z - b.z) <= POINT_EPSILON
end

local function triangleArea(a, b, c)
    return math.abs(((a.x * (b.z - c.z)) + (b.x * (c.z - a.z)) + (c.x * (a.z - b.z))) * 0.5)
end

local function getEffectiveVertexCount(poly)
    local count = #poly
    if count >= 2 and pointsEqual2d(poly[1], poly[count]) then
        return count - 1
    end
    return count
end

local function buildEffectivePolygon(poly)
    local effectiveCount = getEffectiveVertexCount(poly)
    local effective = table.create(effectiveCount)
    for i = 1, effectiveCount do
        effective[i] = poly[i]
    end
    return effective
end

local function buildSimplifiedPolygon(poly)
    local effectiveCount = getEffectiveVertexCount(poly)
    local simplified = {}
    local mapping = {}

    for i = 1, effectiveCount do
        local point = poly[i]
        if #simplified == 0 or not pointsEqual2d(simplified[#simplified], point) then
            simplified[#simplified + 1] = point
            mapping[#mapping + 1] = i
        end
    end

    local changed = true
    while changed and #simplified >= 3 do
        changed = false
        for i = 1, #simplified do
            local prevIndex = ((i - 2) % #simplified) + 1
            local nextIndex = (i % #simplified) + 1
            if
                math.abs(orient2d(simplified[prevIndex], simplified[i], simplified[nextIndex]))
                <= POINT_EPSILON
            then
                table.remove(simplified, i)
                table.remove(mapping, i)
                changed = true
                break
            end
        end
    end

    return simplified, mapping
end

local function normalizeTriangleIndices(poly, indices)
    if type(indices) ~= "table" or #indices < 3 or (#indices % 3) ~= 0 then
        return nil
    end

    local effectiveCount = getEffectiveVertexCount(poly)
    local hasClosingDuplicate = effectiveCount < #poly
    if effectiveCount < 3 then
        return nil
    end

    local minIndex = math.huge
    local maxIndex = -math.huge
    for _, rawIndex in ipairs(indices) do
        if type(rawIndex) ~= "number" then
            return nil
        end
        if rawIndex < minIndex then
            minIndex = rawIndex
        end
        if rawIndex > maxIndex then
            maxIndex = rawIndex
        end
    end

    local indexingMode = nil
    if
        minIndex == 0
        and maxIndex <= (hasClosingDuplicate and effectiveCount or (effectiveCount - 1))
    then
        indexingMode = "zero"
    elseif
        minIndex == 1
        and maxIndex <= (hasClosingDuplicate and (effectiveCount + 1) or effectiveCount)
    then
        indexingMode = "one"
    else
        return nil
    end

    local triangles = table.create(#indices / 3)
    local effectivePoly = buildEffectivePolygon(poly)

    local function remapIndex(rawIndex)
        if indexingMode == "zero" then
            if hasClosingDuplicate and rawIndex == effectiveCount then
                return 1
            end
            return rawIndex + 1
        end

        if hasClosingDuplicate and rawIndex == (effectiveCount + 1) then
            return 1
        end
        return rawIndex
    end

    for i = 1, #indices, 3 do
        local i1 = remapIndex(indices[i])
        local i2 = remapIndex(indices[i + 1])
        local i3 = remapIndex(indices[i + 2])
        if
            i1 < 1
            or i1 > effectiveCount
            or i2 < 1
            or i2 > effectiveCount
            or i3 < 1
            or i3 > effectiveCount
        then
            return nil
        end
        if i1 ~= i2 and i2 ~= i3 and i1 ~= i3 then
            triangles[#triangles + 1] = { i1, i2, i3 }
        end
    end

    if #triangles == 0 then
        return nil
    end

    local polygonArea = math.abs(signedArea(effectivePoly))
    if polygonArea > POINT_EPSILON then
        local totalTriangleArea = 0
        for _, tri in ipairs(triangles) do
            totalTriangleArea += triangleArea(
                effectivePoly[tri[1]],
                effectivePoly[tri[2]],
                effectivePoly[tri[3]]
            )
        end

        local coverage = totalTriangleArea / polygonArea
        if coverage < 0.95 or coverage > 1.05 then
            return nil
        end
    end

    return triangles
end

--- Ray-casting point-in-polygon test.
--- @param px number X coordinate of test point
--- @param pz number Z coordinate of test point
--- @param poly table Array of {x, z} points forming the polygon
--- @return boolean True if point is inside polygon
function GeoUtils.pointInPolygon(px, pz, poly)
    local inside = false
    local j = #poly
    for i = 1, #poly do
        local xi, zi = poly[i].x, poly[i].z
        local xj, zj = poly[j].x, poly[j].z
        if ((zi > pz) ~= (zj > pz)) and (px < (xj - xi) * (pz - zi) / (zj - zi) + xi) then
            inside = not inside
        end
        j = i
    end
    return inside
end

function GeoUtils.pointInPolygonWithHoles(px, pz, outerPoly, holes)
    if not GeoUtils.pointInPolygon(px, pz, outerPoly) then
        return false
    end
    if holes then
        for _, hole in ipairs(holes) do
            if hole and #hole >= 3 and GeoUtils.pointInPolygon(px, pz, hole) then
                return false
            end
        end
    end
    return true
end

--- Compute bounding box of a polygon.
--- @param poly table Array of {x, z} points
--- @return number, number, number, number minX, minZ, maxX, maxZ
function GeoUtils.polygonBounds(poly)
    local minX, minZ = math.huge, math.huge
    local maxX, maxZ = -math.huge, -math.huge
    for _, pt in ipairs(poly) do
        if pt.x < minX then
            minX = pt.x
        end
        if pt.z < minZ then
            minZ = pt.z
        end
        if pt.x > maxX then
            maxX = pt.x
        end
        if pt.z > maxZ then
            maxZ = pt.z
        end
    end
    return minX, minZ, maxX, maxZ
end

--- Convert chunk-relative footprint to world coordinates.
--- @param footprint table Array of {x, z} points
--- @param originStuds table {x, y, z} chunk origin
--- @return table worldPoly, number minX, number minZ, number maxX, number maxZ
function GeoUtils.toWorldFootprint(footprint, originStuds)
    local worldPoly = table.create(#footprint)
    local minX, minZ = math.huge, math.huge
    local maxX, maxZ = -math.huge, -math.huge
    for i, pt in ipairs(footprint) do
        local wx = pt.x + originStuds.x
        local wz = pt.z + originStuds.z
        worldPoly[i] = { x = wx, z = wz }
        if wx < minX then
            minX = wx
        end
        if wz < minZ then
            minZ = wz
        end
        if wx > maxX then
            maxX = wx
        end
        if wz > maxZ then
            maxZ = wz
        end
    end
    return worldPoly, minX, minZ, maxX, maxZ
end

--- Triangulate a simple polygon described as {x, z} vertices.
--- Uses explicit manifest triangle indices when present; otherwise falls back to
--- ear clipping so concave roofs keep their true footprint.
--- @param poly table Array of {x, z} points
--- @param indices table? Optional explicit triangle indices from the manifest
--- @return table Array of {i1, i2, i3} vertex indices (Luau 1-based)
function GeoUtils.triangulatePolygon(poly, indices)
    if not poly or #poly < 3 then
        return {}
    end

    local indexedTriangles = normalizeTriangleIndices(poly, indices)
    if indexedTriangles then
        return indexedTriangles
    end

    local simplifiedPoly, originalIndexMap = buildSimplifiedPolygon(poly)
    if #simplifiedPoly < 3 then
        return {}
    end

    local vertexOrder = table.create(#simplifiedPoly)
    for i = 1, #simplifiedPoly do
        vertexOrder[i] = i
    end

    if signedArea(simplifiedPoly) < 0 then
        local reversed = table.create(#vertexOrder)
        for i = #vertexOrder, 1, -1 do
            reversed[#reversed + 1] = vertexOrder[i]
        end
        vertexOrder = reversed
    end

    local triangles = {}
    local remaining = #vertexOrder
    local guard = remaining * remaining

    while remaining > 3 and guard > 0 do
        local earFound = false

        for orderIndex = 1, remaining do
            local prevIndex = vertexOrder[((orderIndex - 2) % remaining) + 1]
            local currentIndex = vertexOrder[orderIndex]
            local nextIndex = vertexOrder[(orderIndex % remaining) + 1]
            local prevPoint = simplifiedPoly[prevIndex]
            local currentPoint = simplifiedPoly[currentIndex]
            local nextPoint = simplifiedPoly[nextIndex]

            if orient2d(prevPoint, currentPoint, nextPoint) > POINT_EPSILON then
                local containsOtherPoint = false
                for candidateOrder = 1, remaining do
                    local candidateIndex = vertexOrder[candidateOrder]
                    if
                        candidateIndex ~= prevIndex
                        and candidateIndex ~= currentIndex
                        and candidateIndex ~= nextIndex
                    then
                        local candidate = simplifiedPoly[candidateIndex]
                        if
                            pointInTriangle(
                                candidate.x,
                                candidate.z,
                                prevPoint,
                                currentPoint,
                                nextPoint
                            )
                        then
                            containsOtherPoint = true
                            break
                        end
                    end
                end

                if not containsOtherPoint then
                    triangles[#triangles + 1] = {
                        originalIndexMap[prevIndex],
                        originalIndexMap[currentIndex],
                        originalIndexMap[nextIndex],
                    }
                    table.remove(vertexOrder, orderIndex)
                    remaining -= 1
                    earFound = true
                    break
                end
            end
        end

        if not earFound then
            return {}
        end

        guard -= 1
    end

    if remaining == 3 then
        triangles[#triangles + 1] = {
            originalIndexMap[vertexOrder[1]],
            originalIndexMap[vertexOrder[2]],
            originalIndexMap[vertexOrder[3]],
        }
    end

    return triangles
end

return GeoUtils

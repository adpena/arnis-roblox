local GeoUtils = {}

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

return GeoUtils

local PolygonBatcher = {}

local KEY_SCALE = 1000

local function makeSegmentKey(x0, x1)
    return table.concat({
        tostring(math.floor(x0 * KEY_SCALE + 0.5)),
        tostring(math.floor(x1 * KEY_SCALE + 0.5)),
    }, "|")
end

local function flushActiveRects(activeByKey, rects, stripDepth)
    for key, active in pairs(activeByKey) do
        activeByKey[key] = nil
        rects[#rects + 1] = {
            centerX = (active.x0 + active.x1) * 0.5,
            centerZ = (active.startZ + active.endZ) * 0.5,
            width = active.x1 - active.x0,
            depth = (active.endZ - active.startZ) + stripDepth,
        }
    end
end

local function buildRectsFromSegmentsByRow(rows, stripDepth)
    local rects = {}
    local activeByKey = {}

    for _, row in ipairs(rows) do
        local seen = {}
        for _, segment in ipairs(row.segments) do
            local key = makeSegmentKey(segment.x0, segment.x1)
            seen[key] = true
            local active = activeByKey[key]
            if active then
                active.endZ = row.z
            else
                activeByKey[key] = {
                    x0 = segment.x0,
                    x1 = segment.x1,
                    startZ = row.z,
                    endZ = row.z,
                }
            end
        end

        for key, active in pairs(activeByKey) do
            if not seen[key] then
                activeByKey[key] = nil
                rects[#rects + 1] = {
                    centerX = (active.x0 + active.x1) * 0.5,
                    centerZ = (active.startZ + active.endZ) * 0.5,
                    width = active.x1 - active.x0,
                    depth = (active.endZ - active.startZ) + stripDepth,
                }
            end
        end
    end

    flushActiveRects(activeByKey, rects, stripDepth)
    table.sort(rects, function(a, b)
        if a.centerZ == b.centerZ then
            return a.centerX < b.centerX
        end
        return a.centerZ < b.centerZ
    end)
    return rects
end

function PolygonBatcher.BuildRectsFromRows(rows, stripDepth)
    if not rows or #rows == 0 then
        return {}
    end
    table.sort(rows, function(a, b)
        return a.z < b.z
    end)
    return buildRectsFromSegmentsByRow(rows, stripDepth)
end

function PolygonBatcher.BuildRects(worldPoly, stripDepth)
    if not worldPoly or #worldPoly < 3 then
        return {}
    end

    local minZ, maxZ = math.huge, -math.huge
    for _, point in ipairs(worldPoly) do
        minZ = math.min(minZ, point.Z)
        maxZ = math.max(maxZ, point.Z)
    end

    local rows = {}
    local n = #worldPoly
    local z = minZ + stripDepth * 0.5
    while z <= maxZ do
        local xs = {}
        for i = 1, n do
            local p1 = worldPoly[i]
            local p2 = worldPoly[(i % n) + 1]
            local z1, z2 = p1.Z, p2.Z
            if (z1 <= z and z < z2) or (z2 <= z and z < z1) then
                local t = (z - z1) / (z2 - z1)
                xs[#xs + 1] = p1.X + t * (p2.X - p1.X)
            end
        end
        table.sort(xs)

        local segments = {}
        local i = 1
        while i + 1 <= #xs do
            local x0, x1 = xs[i], xs[i + 1]
            if x1 - x0 > 0.1 then
                segments[#segments + 1] = { x0 = x0, x1 = x1 }
            end
            i += 2
        end

        if #segments > 0 then
            rows[#rows + 1] = {
                z = z,
                segments = segments,
            }
        end
        z += stripDepth
    end

    return PolygonBatcher.BuildRectsFromRows(rows, stripDepth)
end

function PolygonBatcher.BuildRectsFromCells(cells, gridSize)
    if not cells or #cells == 0 then
        return {}
    end

    local rowsByZ = {}
    for _, cell in ipairs(cells) do
        local key = math.floor(cell.z * KEY_SCALE + 0.5)
        local row = rowsByZ[key]
        if not row then
            row = {
                z = cell.z,
                xs = {},
            }
            rowsByZ[key] = row
        end
        row.xs[#row.xs + 1] = cell.x
    end

    local rows = {}
    for _, row in pairs(rowsByZ) do
        table.sort(row.xs)
        local segments = {}
        local runStart = nil
        local runEnd = nil
        for _, x in ipairs(row.xs) do
            if not runStart then
                runStart = x
                runEnd = x
            elseif math.abs(x - runEnd - gridSize) <= 1e-6 then
                runEnd = x
            else
                segments[#segments + 1] = {
                    x0 = runStart - gridSize * 0.5,
                    x1 = runEnd + gridSize * 0.5,
                }
                runStart = x
                runEnd = x
            end
        end
        if runStart then
            segments[#segments + 1] = {
                x0 = runStart - gridSize * 0.5,
                x1 = runEnd + gridSize * 0.5,
            }
        end
        rows[#rows + 1] = {
            z = row.z,
            segments = segments,
        }
    end

    return PolygonBatcher.BuildRectsFromRows(rows, gridSize)
end

function PolygonBatcher.BuildGridCells(worldPoly, gridSize)
    if not worldPoly or #worldPoly < 3 then
        return {}
    end

    local minX, minZ, maxZ = math.huge, math.huge, -math.huge
    for _, point in ipairs(worldPoly) do
        minX = math.min(minX, point.x or point.X)
        minZ = math.min(minZ, point.z or point.Z)
        maxZ = math.max(maxZ, point.z or point.Z)
    end

    local cells = {}
    local rowBaseX = minX + gridSize * 0.5
    local z = minZ + gridSize * 0.5
    local n = #worldPoly

    while z <= maxZ do
        local xs = {}
        for i = 1, n do
            local p1 = worldPoly[i]
            local p2 = worldPoly[(i % n) + 1]
            local x1 = p1.x or p1.X
            local z1 = p1.z or p1.Z
            local x2 = p2.x or p2.X
            local z2 = p2.z or p2.Z
            if (z1 <= z and z < z2) or (z2 <= z and z < z1) then
                local t = (z - z1) / (z2 - z1)
                xs[#xs + 1] = x1 + t * (x2 - x1)
            end
        end
        table.sort(xs)

        local i = 1
        while i + 1 <= #xs do
            local x0 = xs[i]
            local x1 = xs[i + 1]
            if x1 - x0 > 0.1 then
                local startIndex = math.ceil((x0 - rowBaseX) / gridSize)
                local endIndex = math.floor((x1 - rowBaseX) / gridSize)
                for gridIndex = startIndex, endIndex do
                    cells[#cells + 1] = {
                        x = rowBaseX + gridIndex * gridSize,
                        z = z,
                    }
                end
            end
            i += 2
        end

        z += gridSize
    end

    return cells
end

return PolygonBatcher

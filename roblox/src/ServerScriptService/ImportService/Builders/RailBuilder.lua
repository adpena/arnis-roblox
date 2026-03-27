local Workspace = game:GetService("Workspace")

local RailBuilder = {}

local RAIL_THICKNESS = 1

local function offsetPoint(point, origin)
    return Vector3.new(point.x + origin.x, point.y + origin.y, point.z + origin.z)
end

local function paintSegment(terrain, p1, p2, width)
    local delta = p2 - p1
    local length = delta.Magnitude
    if length < 0.01 then
        return
    end

    -- Use per-vertex Y so FillBlock tilts to follow terrain slope.
    local startPos = Vector3.new(p1.X, p1.Y - RAIL_THICKNESS * 0.5, p1.Z)
    local endPos = Vector3.new(p2.X, p2.Y - RAIL_THICKNESS * 0.5, p2.Z)
    local midPos = (startPos + endPos) * 0.5
    local cf = CFrame.lookAt(midPos, endPos)
    terrain:FillBlock(cf, Vector3.new(width, RAIL_THICKNESS, length), Enum.Material.Cobblestone)
end

local function emitAuditRecord(parent, rail, builtSegmentCount)
    if parent == nil or builtSegmentCount <= 0 then
        return
    end
    local record = Instance.new("Configuration")
    local railId = tostring(rail.id or "rail")
    record.Name = "RailAudit_" .. railId
    record:SetAttribute("ArnisRailAuditRecord", true)
    record:SetAttribute("ArnisRailKind", tostring(rail.kind or "unknown"))
    record:SetAttribute("ArnisRailSourceId", railId)
    record:SetAttribute("ArnisRailSegmentCount", builtSegmentCount)
    record:SetAttribute("ArnisRailWidthStuds", tonumber(rail.widthStuds) or 4)
    record.Parent = parent
end

function RailBuilder.BuildAll(parent, rails, originStuds)
    if not rails or #rails == 0 then
        return
    end
    for _, rail in ipairs(rails) do
        RailBuilder.FallbackBuild(parent, rail, originStuds)
    end
end

function RailBuilder.Build(parent, rail, originStuds)
    RailBuilder.FallbackBuild(parent, rail, originStuds)
end

function RailBuilder.FallbackBuild(parent, rail, originStuds)
    local terrain = Workspace.Terrain
    local width = rail.widthStuds or 4
    local builtSegmentCount = 0
    for i = 1, #rail.points - 1 do
        local p1 = offsetPoint(rail.points[i], originStuds)
        local p2 = offsetPoint(rail.points[i + 1], originStuds)
        paintSegment(terrain, p1, p2, width)
        builtSegmentCount += 1
    end
    emitAuditRecord(parent, rail, builtSegmentCount)
end

return RailBuilder

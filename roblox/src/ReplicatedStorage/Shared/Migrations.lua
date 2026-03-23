local Migrations = {}

local function ensurePoint3Y(points)
    for _, point in ipairs(points or {}) do
        if point.y == nil then
            point.y = 0
        end
    end
end

local function ensureLegacyFootprint(footprint)
    if footprint ~= nil and #footprint >= 3 then
        return footprint
    end

    return {
        { x = 0, z = 0 },
        { x = 1, z = 0 },
        { x = 1, z = 1 },
    }
end

local function normalizeLegacyRoadFeature(road)
    if road == nil then
        return
    end

    if road.kind == nil or road.kind == "" then
        road.kind = "road"
    end

    if road.material == nil or road.material == "" then
        road.material = "Asphalt"
    end

    if road.widthStuds == nil then
        road.widthStuds = 10
    end

    if road.hasSidewalk == nil then
        road.hasSidewalk = false
    end

    ensurePoint3Y(road.points)

    if road.elevated == nil then
        road.elevated = false
    end

    if road.tunnel == nil then
        road.tunnel = false
    end
end

local function normalizeLegacyRailFeature(rail)
    if rail == nil then
        return
    end

    if rail.kind == nil or rail.kind == "" then
        rail.kind = "rail"
    end

    if rail.material == nil or rail.material == "" then
        rail.material = "Metal"
    end

    if rail.widthStuds == nil then
        rail.widthStuds = 6
    end

    ensurePoint3Y(rail.points)
end

local function normalizeLegacyRoom(room)
    if room == nil then
        return
    end

    if room.id == nil or room.id == "" then
        room.id = "room"
    end

    if room.name == nil or room.name == "" then
        room.name = room.id
    end

    room.footprint = ensureLegacyFootprint(room.footprint)

    if room.floorY == nil then
        room.floorY = 0
    end

    if room.height == nil then
        room.height = 3
    end
end

local function normalizeLegacyBuildingFeature(building)
    if building == nil then
        return
    end

    if not building.material then
        building.material = "Concrete"
    end

    if not building.roof then
        building.roof = "flat"
    end

    building.footprint = ensureLegacyFootprint(building.footprint)

    if building.baseY == nil then
        building.baseY = 0
    end

    if building.height == nil then
        building.height = math.max(building.levels or 1, 1) * 14
    end

    if not building.rooms then
        building.rooms = {}
    end

    for _, room in ipairs(building.rooms) do
        normalizeLegacyRoom(room)
    end
end

local function normalizeLegacyWaterFeature(water)
    if water == nil then
        return
    end

    if water.kind == nil or water.kind == "" then
        if water.points ~= nil then
            water.kind = "river"
        elseif water.footprint ~= nil then
            water.kind = "lake"
        else
            water.kind = "water"
        end
    end

    if water.material == nil or water.material == "" then
        water.material = "Water"
    end

    if water.holes == nil then
        water.holes = {}
    end
end

-- Migrate from old versions to the latest schema
function Migrations.migrate(manifest, targetVersion)
    local current = manifest.schemaVersion or "0.1.0"

    if current == targetVersion then
        return manifest
    end

    local migrated = manifest

    if current == "0.1.0" then
        migrated = Migrations.migrate_010_to_020(migrated)
        current = "0.2.0"
    end

    if current == "0.2.0" then
        migrated = Migrations.migrate_020_to_030(migrated)
        current = "0.3.0"
    end

    if current == "0.3.0" then
        migrated = Migrations.migrate_030_to_040(migrated)
        current = "0.4.0"
    end

    migrated.schemaVersion = targetVersion
    return migrated
end

function Migrations.migrate_010_to_020(manifest)
    -- Add mandatory 0.2.0 fields if missing
    if not manifest.meta.totalFeatures then
        local total = 0
        for _, chunk in ipairs(manifest.chunks) do
            total += #(chunk.roads or {})
            total += #(chunk.rails or {})
            total += #(chunk.buildings or {})
            total += #(chunk.water or {})
            total += #(chunk.props or {})
        end
        manifest.meta.totalFeatures = total
    end

    for _, chunk in ipairs(manifest.chunks) do
        for _, road in ipairs(chunk.roads or {}) do
            normalizeLegacyRoadFeature(road)
        end
        for _, rail in ipairs(chunk.rails or {}) do
            normalizeLegacyRailFeature(rail)
        end
        for _, building in ipairs(chunk.buildings or {}) do
            normalizeLegacyBuildingFeature(building)
        end
        for _, water in ipairs(chunk.water or {}) do
            normalizeLegacyWaterFeature(water)
        end
    end

    return manifest
end

function Migrations.migrate_020_to_030(manifest)
    for _, chunk in ipairs(manifest.chunks or {}) do
        if chunk.terrain and chunk.terrain.materials == nil then
            chunk.terrain.materials = nil
        end

        for _, road in ipairs(chunk.roads or {}) do
            normalizeLegacyRoadFeature(road)
        end

        for _, rail in ipairs(chunk.rails or {}) do
            normalizeLegacyRailFeature(rail)
        end

        for _, building in ipairs(chunk.buildings or {}) do
            normalizeLegacyBuildingFeature(building)
        end

        for _, water in ipairs(chunk.water or {}) do
            normalizeLegacyWaterFeature(water)
        end

        chunk.landuse = chunk.landuse or {}
        chunk.barriers = chunk.barriers or {}
    end

    return manifest
end

function Migrations.migrate_030_to_040(manifest)
    local oldMps = manifest.meta.metersPerStud or 1.0
    local newMps = 0.3
    local scaleFactor = oldMps / newMps

    if math.abs(scaleFactor - 1.0) < 0.001 then
        return manifest
    end

    manifest.meta.metersPerStud = newMps
    manifest.meta.chunkSizeStuds = manifest.meta.chunkSizeStuds * scaleFactor

    for _, chunk in ipairs(manifest.chunks or {}) do
        chunk.originStuds.x = chunk.originStuds.x * scaleFactor
        chunk.originStuds.y = chunk.originStuds.y * scaleFactor
        chunk.originStuds.z = chunk.originStuds.z * scaleFactor

        if chunk.terrain then
            chunk.terrain.cellSizeStuds = chunk.terrain.cellSizeStuds * scaleFactor
            for i, h in ipairs(chunk.terrain.heights) do
                chunk.terrain.heights[i] = h * scaleFactor
            end
        end

        for _, road in ipairs(chunk.roads or {}) do
            normalizeLegacyRoadFeature(road)
            road.widthStuds = road.widthStuds * scaleFactor
            for _, pt in ipairs(road.points or {}) do
                pt.x = pt.x * scaleFactor
                pt.y = pt.y * scaleFactor
                pt.z = pt.z * scaleFactor
            end
            if road.elevated == nil then
                road.elevated = false
            end
            if road.tunnel == nil then
                road.tunnel = false
            end
        end

        for _, rail in ipairs(chunk.rails or {}) do
            normalizeLegacyRailFeature(rail)
            rail.widthStuds = rail.widthStuds * scaleFactor
            for _, pt in ipairs(rail.points or {}) do
                pt.x = pt.x * scaleFactor
                pt.y = pt.y * scaleFactor
                pt.z = pt.z * scaleFactor
            end
        end

        for _, building in ipairs(chunk.buildings or {}) do
            normalizeLegacyBuildingFeature(building)
            building.baseY = building.baseY * scaleFactor
            building.height = building.height * scaleFactor
            for _, pt in ipairs(building.footprint or {}) do
                pt.x = pt.x * scaleFactor
                pt.z = pt.z * scaleFactor
            end
            if building.color and not building.wallColor then
                building.wallColor = building.color
                building.color = nil
            end
            for _, room in ipairs(building.rooms or {}) do
                room.floorY = room.floorY * scaleFactor
                room.height = room.height * scaleFactor
                for _, pt in ipairs(room.footprint or {}) do
                    pt.x = pt.x * scaleFactor
                    pt.z = pt.z * scaleFactor
                end
            end
        end

        for _, water in ipairs(chunk.water or {}) do
            if water.widthStuds then
                water.widthStuds = water.widthStuds * scaleFactor
            end
            for _, pt in ipairs(water.points or {}) do
                pt.x = pt.x * scaleFactor
                pt.y = pt.y * scaleFactor
                pt.z = pt.z * scaleFactor
            end
            if water.footprint then
                for _, pt in ipairs(water.footprint) do
                    pt.x = pt.x * scaleFactor
                    pt.z = pt.z * scaleFactor
                end
            end
            if water.holes then
                for _, hole in ipairs(water.holes) do
                    for _, pt in ipairs(hole) do
                        pt.x = pt.x * scaleFactor
                        pt.z = pt.z * scaleFactor
                    end
                end
            end
        end

        for _, prop in ipairs(chunk.props or {}) do
            prop.position.x = prop.position.x * scaleFactor
            prop.position.y = prop.position.y * scaleFactor
            prop.position.z = prop.position.z * scaleFactor
        end

        for _, lu in ipairs(chunk.landuse or {}) do
            for _, pt in ipairs(lu.footprint or {}) do
                pt.x = pt.x * scaleFactor
                pt.z = pt.z * scaleFactor
            end
        end

        for _, barrier in ipairs(chunk.barriers or {}) do
            for _, pt in ipairs(barrier.points or {}) do
                pt.x = pt.x * scaleFactor
                pt.y = pt.y * scaleFactor
                pt.z = pt.z * scaleFactor
            end
        end
    end

    return manifest
end

return Migrations

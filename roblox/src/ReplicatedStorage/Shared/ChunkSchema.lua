local Version = require(script.Parent.Version)
local Migrations = require(script.Parent.Migrations)

local ChunkSchema = {}

export type Point2 = {
    x: number,
    z: number,
}

export type Point3 = {
    x: number,
    y: number,
    z: number,
}

export type TerrainGrid = {
    cellSizeStuds: number,
    width: number,
    depth: number,
    heights: { number },
    material: string,
}

local function assertType(value, expectedType, message)
    assert(type(value) == expectedType, message)
end

local function validatePoint3(point, label)
    assertType(point, "table", label .. " must be a table")
    assertType(point.x, "number", label .. ".x must be a number")
    assertType(point.y, "number", label .. ".y must be a number")
    assertType(point.z, "number", label .. ".z must be a number")
end

local function validateOptionalPoint3(point, label)
    if point ~= nil then
        validatePoint3(point, label)
    end
end

local function validatePoint2(point, label)
    assertType(point, "table", label .. " must be a table")
    assertType(point.x, "number", label .. ".x must be a number")
    assertType(point.z, "number", label .. ".z must be a number")
end

function ChunkSchema.validateManifest(manifest)
    assertType(manifest, "table", "manifest must be a table")

    -- 1. Migrate if needed
    if manifest.schemaVersion ~= Version.SchemaVersion then
        manifest = Migrations.migrate(manifest, Version.SchemaVersion)
    end

    -- 2. Validate current version
    assert(manifest.schemaVersion == Version.SchemaVersion, "unexpected schemaVersion after migration")

    assertType(manifest.meta, "table", "manifest.meta must be a table")
    assertType(manifest.meta.worldName, "string", "manifest.meta.worldName must be a string")
    assertType(manifest.meta.generator, "string", "manifest.meta.generator must be a string")
    assertType(manifest.meta.source, "string", "manifest.meta.source must be a string")
    assertType(manifest.meta.metersPerStud, "number", "manifest.meta.metersPerStud must be a number")
    assertType(manifest.meta.chunkSizeStuds, "number", "manifest.meta.chunkSizeStuds must be a number")

    -- 0.2.0+ requirement
    assertType(manifest.meta.totalFeatures, "number", "manifest.meta.totalFeatures must be a number")
    if manifest.meta.canonicalAnchor ~= nil then
        assertType(manifest.meta.canonicalAnchor, "table", "manifest.meta.canonicalAnchor must be a table")
        validateOptionalPoint3(
            manifest.meta.canonicalAnchor.positionStuds,
            "manifest.meta.canonicalAnchor.positionStuds"
        )
        validateOptionalPoint3(
            manifest.meta.canonicalAnchor.positionOffsetFromHeuristicStuds,
            "manifest.meta.canonicalAnchor.positionOffsetFromHeuristicStuds"
        )
        validateOptionalPoint3(
            manifest.meta.canonicalAnchor.lookDirectionStuds,
            "manifest.meta.canonicalAnchor.lookDirectionStuds"
        )
    end

    assertType(manifest.chunks, "table", "manifest.chunks must be an array-like table")
    assert(#manifest.chunks > 0, "manifest.chunks must contain at least one chunk")

    for chunkIndex, chunk in ipairs(manifest.chunks) do
        local prefix = ("manifest.chunks[%d]"):format(chunkIndex)

        assertType(chunk.id, "string", prefix .. ".id must be a string")
        validatePoint3(chunk.originStuds, prefix .. ".originStuds")

        if chunk.terrain ~= nil then
            local terrain = chunk.terrain
            assertType(terrain.cellSizeStuds, "number", prefix .. ".terrain.cellSizeStuds must be a number")
            assertType(terrain.width, "number", prefix .. ".terrain.width must be a number")
            assertType(terrain.depth, "number", prefix .. ".terrain.depth must be a number")
            assertType(terrain.heights, "table", prefix .. ".terrain.heights must be a table")
            assertType(terrain.material, "string", prefix .. ".terrain.material must be a string")
            assert(
                #terrain.heights == terrain.width * terrain.depth,
                prefix .. ".terrain.heights length must equal width * depth"
            )
            if terrain.materials ~= nil then
                assert(
                    #terrain.materials == terrain.width * terrain.depth,
                    prefix .. ".terrain.materials length must equal width * depth"
                )
            end
        end

        for _, road in ipairs(chunk.roads or {}) do
            assertType(road.id, "string", prefix .. ".roads[].id must be a string")
            assertType(road.kind, "string", prefix .. ".roads[].kind must be a string")
            assertType(road.material, "string", prefix .. ".roads[].material must be a string")
            assertType(road.widthStuds, "number", prefix .. ".roads[].widthStuds must be a number")
            assertType(road.hasSidewalk, "boolean", prefix .. ".roads[].hasSidewalk must be a boolean")
            assertType(road.points, "table", prefix .. ".roads[].points must be a table")
            assert(#road.points >= 2, prefix .. ".roads[].points must contain at least two points")
            if road.surface ~= nil then
                assertType(road.surface, "string", prefix .. ".roads[].surface must be a string")
            end
            if road.elevated ~= nil then
                assertType(road.elevated, "boolean", prefix .. ".roads[].elevated must be a boolean")
            end
            if road.tunnel ~= nil then
                assertType(road.tunnel, "boolean", prefix .. ".roads[].tunnel must be a boolean")
            end
            if road.sidewalk ~= nil then
                assertType(road.sidewalk, "string", prefix .. ".roads[].sidewalk must be a string")
            end
            for pointIndex, point in ipairs(road.points) do
                validatePoint3(point, ("%s.roads[].points[%d]"):format(prefix, pointIndex))
            end
        end

        for _, rail in ipairs(chunk.rails or {}) do
            assertType(rail.id, "string", prefix .. ".rails[].id must be a string")
            assertType(rail.kind, "string", prefix .. ".rails[].kind must be a string")
            assertType(rail.material, "string", prefix .. ".rails[].material must be a string")
            assertType(rail.widthStuds, "number", prefix .. ".rails[].widthStuds must be a number")
            assertType(rail.points, "table", prefix .. ".rails[].points must be a table")
            assert(#rail.points >= 2, prefix .. ".rails[].points must contain at least two points")
            for pointIndex, point in ipairs(rail.points) do
                validatePoint3(point, ("%s.rails[].points[%d]"):format(prefix, pointIndex))
            end
        end

        for _, building in ipairs(chunk.buildings or {}) do
            assertType(building.id, "string", prefix .. ".buildings[].id must be a string")
            assertType(building.material, "string", prefix .. ".buildings[].material must be a string")
            assertType(building.footprint, "table", prefix .. ".buildings[].footprint must be a table")
            assert(#building.footprint >= 3, prefix .. ".buildings[].footprint must contain at least three points")
            assertType(building.baseY, "number", prefix .. ".buildings[].baseY must be a number")
            assertType(building.height, "number", prefix .. ".buildings[].height must be a number")
            assertType(building.roof, "string", prefix .. ".buildings[].roof must be a string")
            if building.height_m ~= nil then
                assertType(building.height_m, "number", prefix .. ".buildings[].height_m must be a number")
            end
            if building.levels ~= nil then
                assertType(building.levels, "number", prefix .. ".buildings[].levels must be a number")
            end
            if building.roofLevels ~= nil then
                assertType(building.roofLevels, "number", prefix .. ".buildings[].roofLevels must be a number")
            end
            if building.facadeStyle ~= nil then
                assertType(building.facadeStyle, "string", prefix .. ".buildings[].facadeStyle must be a string")
            end
            if building.wallColor ~= nil then
                assertType(building.wallColor, "table", prefix .. ".buildings[].wallColor must be a table")
            end
            if building.roofColor ~= nil then
                assertType(building.roofColor, "table", prefix .. ".buildings[].roofColor must be a table")
            end
            if building.roofShape ~= nil then
                assertType(building.roofShape, "string", prefix .. ".buildings[].roofShape must be a string")
            end
            if building.roofMaterial ~= nil then
                assertType(building.roofMaterial, "string", prefix .. ".buildings[].roofMaterial must be a string")
            end
            if building.usage ~= nil then
                assertType(building.usage, "string", prefix .. ".buildings[].usage must be a string")
            end
            if building.minHeight ~= nil then
                assertType(building.minHeight, "number", prefix .. ".buildings[].minHeight must be a number")
            end

            for pointIndex, point in ipairs(building.footprint) do
                validatePoint2(point, ("%s.buildings[].footprint[%d]"):format(prefix, pointIndex))
            end

            -- Validate rooms if present
            for roomIndex, room in ipairs(building.rooms or {}) do
                local roomPrefix = ("%s.buildings[].rooms[%d]"):format(prefix, roomIndex)
                assertType(room.id, "string", roomPrefix .. ".id must be a string")
                assertType(room.name, "string", roomPrefix .. ".name must be a string")
                assertType(room.footprint, "table", roomPrefix .. ".footprint must be a table")
                assert(#room.footprint >= 3, roomPrefix .. ".footprint must contain at least three points")
                assertType(room.floorY, "number", roomPrefix .. ".floorY must be a number")
                assertType(room.height, "number", roomPrefix .. ".height must be a number")

                for pointIndex, point in ipairs(room.footprint) do
                    validatePoint2(point, ("%s.footprint[%d]"):format(roomPrefix, pointIndex))
                end
            end
        end

        for _, water in ipairs(chunk.water or {}) do
            assertType(water.id, "string", prefix .. ".water[].id must be a string")
            assertType(water.kind, "string", prefix .. ".water[].kind must be a string")
            assertType(water.material, "string", prefix .. ".water[].material must be a string")
            if water.surfaceY ~= nil then
                assertType(water.surfaceY, "number", prefix .. ".water[].surfaceY must be a number")
            end

            if water.points then
                assertType(water.widthStuds, "number", prefix .. ".water[].widthStuds must be a number")
                assertType(water.points, "table", prefix .. ".water[].points must be a table")
                assert(#water.points >= 2, prefix .. ".water[].points must contain at least two points")
                for pointIndex, point in ipairs(water.points) do
                    validatePoint3(point, ("%s.water[].points[%d]"):format(prefix, pointIndex))
                end
            elseif water.footprint then
                assertType(water.footprint, "table", prefix .. ".water[].footprint must be a table")
                assert(#water.footprint >= 3, prefix .. ".water[].footprint must contain at least three points")
                for pointIndex, point in ipairs(water.footprint) do
                    validatePoint2(point, ("%s.water[].footprint[%d]"):format(prefix, pointIndex))
                end
                -- Validate optional inner rings (islands)
                if water.holes ~= nil then
                    assertType(water.holes, "table", prefix .. ".water[].holes must be a table")
                    for holeIndex, hole in ipairs(water.holes) do
                        if type(hole) == "table" and #hole >= 3 then
                            for pointIndex, point in ipairs(hole) do
                                validatePoint2(
                                    point,
                                    ("%s.water[].holes[%d][%d]"):format(prefix, holeIndex, pointIndex)
                                )
                            end
                        else
                            warn(prefix .. (".water[].holes[%d]: skipping malformed hole"):format(holeIndex))
                        end
                    end
                end
            else
                error(prefix .. ".water[] must have either points or footprint")
            end
        end

        for _, prop in ipairs(chunk.props or {}) do
            assertType(prop.id, "string", prefix .. ".props[].id must be a string")
            assertType(prop.kind, "string", prefix .. ".props[].kind must be a string")
            validatePoint3(prop.position, prefix .. ".props[].position")
            assertType(prop.yawDegrees, "number", prefix .. ".props[].yawDegrees must be a number")
            assertType(prop.scale, "number", prefix .. ".props[].scale must be a number")
            if prop.species ~= nil then
                assertType(prop.species, "string", prefix .. ".props[].species must be a string")
            end
        end

        -- Normalize landuse to an empty table if absent; validate present entries
        chunk.landuse = chunk.landuse or {}
        local validLanduse = {}
        for _, lu in ipairs(chunk.landuse) do
            if
                type(lu.id) == "string"
                and type(lu.kind) == "string"
                and (lu.material == nil or type(lu.material) == "string")
                and type(lu.footprint) == "table"
                and #lu.footprint >= 3
            then
                for pointIndex, point in ipairs(lu.footprint) do
                    validatePoint2(point, ("%s.landuse[].footprint[%d]"):format(prefix, pointIndex))
                end
                table.insert(validLanduse, lu)
            else
                warn(
                    prefix
                        .. ".landuse[]: skipping entry with invalid/missing fields (id="
                        .. tostring(lu.id)
                        .. " kind="
                        .. tostring(lu.kind)
                        .. " footprint="
                        .. tostring(lu.footprint and #lu.footprint or 0)
                        .. " pts)"
                )
            end
        end
        chunk.landuse = validLanduse

        -- barriers is optional; validate present entries
        chunk.barriers = chunk.barriers or {}
        local validBarriers = {}
        for _, barrier in ipairs(chunk.barriers) do
            if
                type(barrier.id) == "string"
                and type(barrier.kind) == "string"
                and type(barrier.points) == "table"
                and #barrier.points >= 2
            then
                for pointIndex, point in ipairs(barrier.points) do
                    validatePoint3(point, ("%s.barriers[].points[%d]"):format(prefix, pointIndex))
                end
                table.insert(validBarriers, barrier)
            else
                warn(prefix .. ".barriers[]: skipping entry with invalid/missing fields")
            end
        end
        chunk.barriers = validBarriers
    end

    return manifest
end

return ChunkSchema

local Migrations = {}

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
    
    -- Future migrations here
    
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
            if not road.material then
                road.material = "Asphalt"
            end
        end
        for _, building in ipairs(chunk.buildings or {}) do
            if not building.material then
                building.material = "Concrete"
            end
            if not building.roof then
                building.roof = "flat"
            end
            if not building.rooms then
                building.rooms = {}
            end
        end
        for _, water in ipairs(chunk.water or {}) do
            if not water.material then
                water.material = "Water"
            end
        end
    end

    return manifest
end

return Migrations

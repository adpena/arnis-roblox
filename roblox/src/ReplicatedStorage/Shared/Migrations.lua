local Migrations = {}

local Logger = require(script.Parent.Logger)

local migrationRegistry = {}

function Migrations.register(fromVersion, toVersion, migrateFn)
    migrationRegistry[fromVersion] = {
        to = toVersion,
        migrate = migrateFn,
    }
end

-- 0.1.0 -> 0.2.0 Migration Example:
-- Let's say 0.2.0 adds a 'totalFeatures' count to the meta for quick sanity checks.
Migrations.register("0.1.0", "0.2.0", function(manifest)
    Logger.info("Migrating manifest from 0.1.0 to 0.2.0")
    
    local totalFeatures = 0
    for _, chunk in ipairs(manifest.chunks) do
        totalFeatures += #(chunk.roads or {})
        totalFeatures += #(chunk.buildings or {})
        totalFeatures += #(chunk.water or {})
        totalFeatures += #(chunk.props or {})
    end
    
    manifest.meta.totalFeatures = totalFeatures
    manifest.schemaVersion = "0.2.0"
    
    return manifest
end)

function Migrations.migrate(manifest, targetVersion)
    local currentVersion = manifest.schemaVersion
    
    while currentVersion ~= targetVersion do
        local migration = migrationRegistry[currentVersion]
        if not migration then
            Logger.error(("No migration found from version %s"):format(currentVersion))
            break
        end
        
        manifest = migration.migrate(manifest)
        currentVersion = manifest.schemaVersion
    end
    
    return manifest
end

return Migrations

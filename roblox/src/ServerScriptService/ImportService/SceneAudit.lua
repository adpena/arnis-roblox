local CollectionService = game:GetService("CollectionService")

local SceneAudit = {}

local function normalizeBucketValue(value, fallback)
    if type(value) == "string" and value ~= "" then
        return string.lower(value)
    end
    return fallback
end

local function appendSourceIds(row, sourceIds)
    if type(sourceIds) ~= "string" or sourceIds == "" then
        return
    end
    if row.sourceIds == nil then
        row.sourceIds = {}
    end
    if row._sourceIdSet == nil then
        row._sourceIdSet = {}
        for _, existing in ipairs(row.sourceIds) do
            row._sourceIdSet[existing] = true
        end
    end
    for sourceId in string.gmatch(sourceIds, "([^\n]+)") do
        if row._sourceIdSet[sourceId] ~= true then
            row._sourceIdSet[sourceId] = true
            row.sourceIds[#row.sourceIds + 1] = sourceId
        end
    end
end

local function incrementWaterSurfaceBucket(container, bucket, sourceIds)
    local row = container[bucket]
    if row == nil then
        row = {
            surfacePartCount = 0,
            sourceIds = {},
            _sourceIdSet = {},
        }
        container[bucket] = row
    end
    row.surfacePartCount += 1
    appendSourceIds(row, sourceIds)
end

local function incrementRoadSurfaceBucket(container, bucket, featureCount, sourceIds)
    local row = container[bucket]
    if row == nil then
        row = {
            surfacePartCount = 0,
            featureCount = 0,
            sourceIds = {},
            _sourceIdSet = {},
        }
        container[bucket] = row
    end
    row.surfacePartCount += 1
    row.featureCount += math.max(tonumber(featureCount) or 1, 0)
    appendSourceIds(row, sourceIds)
end

local function incrementInstanceBucket(container, bucket, sourceId)
    local row = container[bucket]
    if row == nil then
        row = {
            instanceCount = 0,
            sourceIds = {},
            _sourceIdSet = {},
        }
        container[bucket] = row
    end
    row.instanceCount += 1
    appendSourceIds(row, sourceId)
end

local function incrementRailBucket(container, bucket, sourceId)
    local row = container[bucket]
    if row == nil then
        row = {
            instanceCount = 0,
            sourceIds = {},
            _sourceIdSet = {},
        }
        container[bucket] = row
    end
    row.instanceCount += 1
    appendSourceIds(row, sourceId)
end

local function incrementBuildingMaterialBucket(container, bucket, sourceId)
    local row = container[bucket]
    if row == nil then
        row = {
            buildingModelCount = 0,
            sourceIds = {},
            _sourceIdSet = {},
        }
        container[bucket] = row
    end
    row.buildingModelCount += 1
    appendSourceIds(row, sourceId)
end

local function incrementTreeConnectivityBucket(container, bucket, connectivityKind)
    local row = container[bucket]
    if row == nil then
        row = {
            treeInstanceCount = 0,
            connectedCount = 0,
            missingTrunkCount = 0,
            missingCanopyCount = 0,
            detachedCanopyCount = 0,
        }
        container[bucket] = row
    end
    row.treeInstanceCount += 1
    if connectivityKind == "connected" then
        row.connectedCount += 1
    elseif connectivityKind == "missing_trunk" then
        row.missingTrunkCount += 1
    elseif connectivityKind == "missing_canopy" then
        row.missingCanopyCount += 1
    else
        row.detachedCanopyCount += 1
    end
end

local function inferProceduralTreeKind(instance)
    local attrKind = instance:GetAttribute("ArnisProceduralVegetationKind")
    if type(attrKind) == "string" and attrKind ~= "" then
        return string.lower(attrKind)
    end
    local lowerName = string.lower(instance.Name)
    local baseName = string.match(lowerName, "^(.-)_tree$")
    if type(baseName) == "string" and baseName ~= "" then
        return baseName
    end
    return "unknown"
end

local function newSummary()
    return {
        chunkCount = 0,
        chunkIds = {},
        basePartCount = 0,
        meshPartCount = 0,
        buildingModelCount = 0,
        buildingDetailPartCount = 0,
        buildingShellPartCount = 0,
        buildingShellMeshPartCount = 0,
        buildingRoofPartCount = 0,
        buildingModelsWithRoofClosureDeck = 0,
        buildingFacadePartCount = 0,
        buildingModelsWithDirectRoof = 0,
        buildingModelsWithMergedRoofOnly = 0,
        buildingModelsWithNoRoofEvidence = 0,
        buildingModelsWithRoof = 0,
        buildingModelsWithoutRoof = 0,
        buildingRoofCoverageByUsage = {},
        buildingRoofCoverageByShape = {},
        buildingModelCountByWallMaterial = {},
        buildingModelCountByRoofMaterial = {},
        buildingModelsWithDirectShell = 0,
        buildingModelsMissingDirectShell = 0,
        mergedBuildingMeshPartCount = 0,
        roadTaggedPartCount = 0,
        roadMeshPartCount = 0,
        roadDetailPartCount = 0,
        roadSurfacePartCount = 0,
        sidewalkSurfacePartCount = 0,
        crossingSurfacePartCount = 0,
        curbSurfacePartCount = 0,
        roadSurfacePartCountByKind = {},
        roadSurfacePartCountBySubkind = {},
        propInstanceCount = 0,
        propInstanceCountByKind = {},
        ambientPropInstanceCount = 0,
        ambientPropInstanceCountByKind = {},
        treeInstanceCount = 0,
        treeInstanceCountBySpecies = {},
        treeModelsWithConnectedTrunkCanopy = 0,
        treeModelsMissingTrunk = 0,
        treeModelsMissingCanopy = 0,
        treeModelsWithDetachedCanopy = 0,
        treeConnectivityBySpecies = {},
        proceduralTreeInstanceCount = 0,
        proceduralTreeModelsWithConnectedTrunkCanopy = 0,
        proceduralTreeModelsMissingTrunk = 0,
        proceduralTreeModelsMissingCanopy = 0,
        proceduralTreeModelsWithDetachedCanopy = 0,
        proceduralTreeConnectivityByKind = {},
        vegetationInstanceCount = 0,
        vegetationInstanceCountByKind = {},
        waterSurfacePartCount = 0,
        waterSurfacePartCountByType = {},
        waterSurfacePartCountByKind = {},
        railReceiptCount = 0,
        railReceiptCountByKind = {},
        roadCrosswalkStripeCount = 0,
        roadTunnelWallCount = 0,
        roadBridgeSupportCount = 0,
        chunksWithBuildingModels = 0,
        chunksWithRoadGeometry = 0,
        chunksWithSidewalkSurfaces = 0,
        chunksWithCrossingSurfaces = 0,
        chunksWithCurbSurfaces = 0,
        chunksWithProps = 0,
        chunksWithVegetation = 0,
        chunksWithAmbientProps = 0,
        chunksWithWaterGeometry = 0,
        chunksWithRailGeometry = 0,
    }
end

local function countDescendants(root, predicate)
    local count = 0
    for _, descendant in ipairs(root:GetDescendants()) do
        if predicate(descendant) then
            count += 1
        end
    end
    return count
end

local function isRoofPart(instance)
    return instance:IsA("BasePart")
        and string.find(instance.Name, "_roof", 1, true) ~= nil
        and string.find(instance.Name, "_roof_closure", 1, true) == nil
end

local function isRoofClosurePart(instance)
    return instance:IsA("BasePart") and string.find(instance.Name, "_roof_closure", 1, true) ~= nil
end

local function isFacadePart(instance)
    return instance:IsA("BasePart") and string.find(instance.Name, "_facade_", 1, true) ~= nil
end

local function inferPropKind(instance)
    local attrKind = instance:GetAttribute("ArnisPropKind")
    if type(attrKind) == "string" and attrKind ~= "" then
        return string.lower(attrKind)
    end
    local pooledKind = instance:GetAttribute("PoolKind")
    if type(pooledKind) == "string" and pooledKind ~= "" then
        return string.lower(pooledKind)
    end
    local name = string.lower(instance.Name)
    if string.find(name, "tree", 1, true) then
        return "tree"
    elseif string.find(name, "fountain", 1, true) then
        return "fountain"
    end
    return "unknown"
end

local function isNamedTreePart(instance, token)
    return instance:IsA("BasePart") and string.find(string.lower(instance.Name), token, 1, true) ~= nil
end

local function collectTreeParts(treeRoot)
    local trunks = {}
    local canopies = {}
    for _, descendant in ipairs(treeRoot:GetDescendants()) do
        if isNamedTreePart(descendant, "trunk") then
            trunks[#trunks + 1] = descendant
        elseif isNamedTreePart(descendant, "canopy") or isNamedTreePart(descendant, "frond") then
            canopies[#canopies + 1] = descendant
        end
    end
    return trunks, canopies
end

local function getPartTopY(part)
    return part.Position.Y + part.Size.Y * 0.5
end

local function getPartBottomY(part)
    return part.Position.Y - part.Size.Y * 0.5
end

local function partsOverlapXZ(a, b, tolerance)
    return math.abs(a.Position.X - b.Position.X) <= (a.Size.X + b.Size.X) * 0.5 + tolerance
        and math.abs(a.Position.Z - b.Position.Z) <= (a.Size.Z + b.Size.Z) * 0.5 + tolerance
end

local function classifyTreeConnectivity(treeRoot)
    local trunks, canopies = collectTreeParts(treeRoot)
    if #trunks == 0 then
        return "missing_trunk"
    end
    if #canopies == 0 then
        return "missing_canopy"
    end

    for _, trunk in ipairs(trunks) do
        local trunkTopY = getPartTopY(trunk)
        for _, canopy in ipairs(canopies) do
            if partsOverlapXZ(trunk, canopy, 0.75) and getPartBottomY(canopy) - trunkTopY <= 1.5 then
                return "connected"
            end
        end
    end

    return "detached_canopy"
end

local function isAuthoredPropRoot(instance)
    return instance:IsA("BasePart") or instance:IsA("Model")
end

local function iterPropRoots(propsFolder)
    local authoredRoots = {}
    local ambientRoots = {}
    if not propsFolder then
        return authoredRoots, ambientRoots
    end

    local detailFolder = propsFolder:FindFirstChild("Detail")
    if detailFolder then
        for _, child in ipairs(detailFolder:GetChildren()) do
            if isAuthoredPropRoot(child) then
                table.insert(authoredRoots, child)
            end
        end
    end

    for _, child in ipairs(propsFolder:GetChildren()) do
        if child == detailFolder then
            continue
        end
        if isAuthoredPropRoot(child) then
            table.insert(ambientRoots, child)
        end
    end

    return authoredRoots, ambientRoots
end

local function incrementRoofEvidenceBucket(container, bucket, evidenceKind)
    local row = container[bucket]
    if row == nil then
        row = {
            buildingModelCount = 0,
            withRoofCount = 0,
            withoutRoofCount = 0,
            directRoofCount = 0,
            mergedRoofOnlyCount = 0,
            noRoofEvidenceCount = 0,
            closureDeckCount = 0,
        }
        container[bucket] = row
    end
    row.buildingModelCount += 1
    if evidenceKind == "direct" then
        row.withRoofCount += 1
        row.directRoofCount += 1
    elseif evidenceKind == "merged_only" then
        row.withRoofCount += 1
        row.mergedRoofOnlyCount += 1
    else
        row.withoutRoofCount += 1
        row.noRoofEvidenceCount += 1
    end
end

local function incrementRoofClosureBucket(container, bucket)
    local row = container[bucket]
    if row == nil then
        row = {
            buildingModelCount = 0,
            withRoofCount = 0,
            withoutRoofCount = 0,
            directRoofCount = 0,
            mergedRoofOnlyCount = 0,
            noRoofEvidenceCount = 0,
            closureDeckCount = 0,
        }
        container[bucket] = row
    end
    row.closureDeckCount += 1
end

function SceneAudit.summarizeWorld(worldRoot)
    local scene = newSummary()
    if not worldRoot then
        return scene
    end

    for _, descendant in ipairs(worldRoot:GetDescendants()) do
        if descendant:IsA("BasePart") then
            scene.basePartCount += 1
            if descendant:IsA("MeshPart") then
                scene.meshPartCount += 1
            end
        end
    end

    for _, child in ipairs(worldRoot:GetChildren()) do
        if not child:IsA("Folder") or child.Name == "PreviewFocus" then
            continue
        end

        scene.chunkCount += 1
        table.insert(scene.chunkIds, child.Name)

        local chunkBuildingModels = 0
        local chunkRoadParts = 0
        local chunkSidewalkSurfaceParts = 0
        local chunkCrossingSurfaceParts = 0
        local chunkCurbSurfaceParts = 0
        local chunkPropInstances = 0
        local chunkVegetationInstances = 0
        local chunkAmbientPropInstances = 0
        local chunkWaterSurfaceParts = 0
        local chunkRailReceipts = 0

        local buildingsFolder = child:FindFirstChild("Buildings")
        if buildingsFolder then
            local mergedMeshes = buildingsFolder:FindFirstChild("MergedMeshes")
            if mergedMeshes then
                scene.mergedBuildingMeshPartCount += countDescendants(mergedMeshes, function(descendant)
                    return descendant:IsA("BasePart")
                end)
            end

            for _, building in ipairs(buildingsFolder:GetChildren()) do
                if building:IsA("Model") and building:GetAttribute("ArnisImportBuildingHeight") ~= nil then
                    chunkBuildingModels += 1
                    local shellFolder = building:FindFirstChild("Shell")
                    local detailFolder = building:FindFirstChild("Detail")
                    local shellParts = shellFolder
                            and countDescendants(shellFolder, function(descendant)
                                return descendant:IsA("BasePart")
                            end)
                        or 0
                    local shellMeshParts = shellFolder
                            and countDescendants(shellFolder, function(descendant)
                                return descendant:IsA("MeshPart")
                            end)
                        or 0
                    local roofParts = shellFolder and countDescendants(shellFolder, isRoofPart) or 0
                    local roofClosureParts = shellFolder and countDescendants(shellFolder, isRoofClosurePart) or 0
                    local detailParts = detailFolder
                            and countDescendants(detailFolder, function(descendant)
                                return descendant:IsA("BasePart")
                            end)
                        or 0
                    local facadeParts = detailFolder and countDescendants(detailFolder, isFacadePart) or 0

                    scene.buildingShellPartCount += shellParts
                    scene.buildingShellMeshPartCount += shellMeshParts
                    scene.buildingRoofPartCount += roofParts
                    scene.buildingDetailPartCount += detailParts
                    scene.buildingFacadePartCount += facadeParts
                    local evidenceKind = "none"
                    if roofParts > 0 then
                        evidenceKind = "direct"
                    elseif building:GetAttribute("ArnisImportHasMergedRoofGeometry") == true then
                        evidenceKind = "merged_only"
                    end
                    local usageBucket =
                        normalizeBucketValue(building:GetAttribute("ArnisImportBuildingUsage"), "unknown")
                    local roofShapeBucket =
                        normalizeBucketValue(building:GetAttribute("ArnisImportRoofShape"), "unknown")
                    local wallMaterialBucket =
                        normalizeBucketValue(building:GetAttribute("ArnisImportWallMaterial"), "unknown")
                    local roofMaterialBucket =
                        normalizeBucketValue(building:GetAttribute("ArnisImportRoofMaterial"), "unknown")
                    local buildingSourceId = building:GetAttribute("ArnisImportSourceId")
                    if type(buildingSourceId) ~= "string" or buildingSourceId == "" then
                        buildingSourceId = building.Name
                    end
                    incrementRoofEvidenceBucket(scene.buildingRoofCoverageByUsage, usageBucket, evidenceKind)
                    incrementRoofEvidenceBucket(scene.buildingRoofCoverageByShape, roofShapeBucket, evidenceKind)
                    incrementBuildingMaterialBucket(
                        scene.buildingModelCountByWallMaterial,
                        wallMaterialBucket,
                        buildingSourceId
                    )
                    incrementBuildingMaterialBucket(
                        scene.buildingModelCountByRoofMaterial,
                        roofMaterialBucket,
                        buildingSourceId
                    )
                    if roofClosureParts > 0 then
                        scene.buildingModelsWithRoofClosureDeck += 1
                        incrementRoofClosureBucket(scene.buildingRoofCoverageByUsage, usageBucket)
                        incrementRoofClosureBucket(scene.buildingRoofCoverageByShape, roofShapeBucket)
                    end
                    if evidenceKind == "direct" then
                        scene.buildingModelsWithDirectRoof += 1
                        scene.buildingModelsWithRoof += 1
                    elseif evidenceKind == "merged_only" then
                        scene.buildingModelsWithMergedRoofOnly += 1
                        scene.buildingModelsWithRoof += 1
                    else
                        scene.buildingModelsWithNoRoofEvidence += 1
                        scene.buildingModelsWithoutRoof += 1
                    end

                    if shellParts > 0 then
                        scene.buildingModelsWithDirectShell += 1
                    else
                        scene.buildingModelsMissingDirectShell += 1
                    end
                end
            end
        end

        local roadsFolder = child:FindFirstChild("Roads")
        if roadsFolder then
            local detailFolder = roadsFolder:FindFirstChild("Detail")
            if detailFolder then
                scene.roadDetailPartCount += countDescendants(detailFolder, function(descendant)
                    return descendant:IsA("BasePart")
                end)
            end

            for _, roadDescendant in ipairs(roadsFolder:GetDescendants()) do
                if roadDescendant:IsA("BasePart") then
                    local role = roadDescendant:GetAttribute("ArnisRoadSurfaceRole")
                    if role == "road" then
                        scene.roadSurfacePartCount += 1
                    elseif role == "sidewalk" then
                        scene.sidewalkSurfacePartCount += 1
                        chunkSidewalkSurfaceParts += 1
                    elseif role == "crossing" then
                        scene.crossingSurfacePartCount += 1
                        chunkCrossingSurfaceParts += 1
                    elseif role == "curb" then
                        scene.curbSurfacePartCount += 1
                        chunkCurbSurfaceParts += 1
                    end
                    if role == "road" or role == "sidewalk" or role == "crossing" or role == "curb" then
                        local kindBucket = normalizeBucketValue(roadDescendant:GetAttribute("ArnisRoadKind"), "unknown")
                        local subkindFallback = role == "road" and "none" or role
                        local subkindBucket =
                            normalizeBucketValue(roadDescendant:GetAttribute("ArnisRoadSubkind"), subkindFallback)
                        local sourceCount = roadDescendant:GetAttribute("ArnisRoadSourceCount")
                        local sourceIds = roadDescendant:GetAttribute("ArnisRoadSourceIds")
                        incrementRoadSurfaceBucket(scene.roadSurfacePartCountByKind, kindBucket, sourceCount, sourceIds)
                        incrementRoadSurfaceBucket(
                            scene.roadSurfacePartCountBySubkind,
                            subkindBucket,
                            sourceCount,
                            sourceIds
                        )
                    end
                end
                if roadDescendant:IsA("BasePart") and CollectionService:HasTag(roadDescendant, "Road") then
                    chunkRoadParts += 1
                    if roadDescendant:IsA("MeshPart") then
                        scene.roadMeshPartCount += 1
                    end
                end
                if roadDescendant:IsA("BasePart") and roadDescendant.Name == "CrosswalkStripe" then
                    scene.roadCrosswalkStripeCount += 1
                elseif roadDescendant:IsA("BasePart") and roadDescendant.Name == "TunnelWall" then
                    scene.roadTunnelWallCount += 1
                elseif roadDescendant:IsA("BasePart") and roadDescendant.Name == "BridgeSupport" then
                    scene.roadBridgeSupportCount += 1
                end
            end
        end

        local waterFolder = child:FindFirstChild("Water")
        if waterFolder then
            for _, waterDescendant in ipairs(waterFolder:GetDescendants()) do
                if waterDescendant:IsA("BasePart") then
                    local waterSurfaceType = waterDescendant:GetAttribute("ArnisWaterSurfaceType")
                    if type(waterSurfaceType) ~= "string" or waterSurfaceType == "" then
                        if string.find(waterDescendant.Name, "PolygonWaterSurface", 1, true) == 1 then
                            waterSurfaceType = "polygon"
                        elseif waterDescendant.Name == "RibbonWaterSurface" then
                            waterSurfaceType = "ribbon"
                        end
                    end
                    if type(waterSurfaceType) == "string" and waterSurfaceType ~= "" then
                        scene.waterSurfacePartCount += 1
                        chunkWaterSurfaceParts += 1
                        incrementWaterSurfaceBucket(
                            scene.waterSurfacePartCountByType,
                            normalizeBucketValue(waterSurfaceType, "unknown"),
                            waterDescendant:GetAttribute("ArnisWaterSourceId")
                        )
                        local waterKind = waterDescendant:GetAttribute("ArnisWaterKind")
                        if type(waterKind) == "string" and waterKind ~= "" then
                            incrementWaterSurfaceBucket(
                                scene.waterSurfacePartCountByKind,
                                normalizeBucketValue(waterKind, "unknown"),
                                waterDescendant:GetAttribute("ArnisWaterSourceId")
                            )
                        end
                    end
                end
            end
        end

        local railsFolder = child:FindFirstChild("Rails")
        if railsFolder then
            for _, railDescendant in ipairs(railsFolder:GetDescendants()) do
                if
                    railDescendant:IsA("Configuration")
                    and railDescendant:GetAttribute("ArnisRailAuditRecord") == true
                then
                    scene.railReceiptCount += 1
                    chunkRailReceipts += 1
                    incrementRailBucket(
                        scene.railReceiptCountByKind,
                        normalizeBucketValue(railDescendant:GetAttribute("ArnisRailKind"), "unknown"),
                        railDescendant:GetAttribute("ArnisRailSourceId")
                    )
                end
            end
        end

        local propsFolder = child:FindFirstChild("Props")
        if propsFolder then
            local authoredPropRoots, ambientPropRoots = iterPropRoots(propsFolder)
            for _, propRoot in ipairs(authoredPropRoots) do
                chunkPropInstances += 1
                scene.propInstanceCount += 1
                local propKind = inferPropKind(propRoot)
                local propSourceId = propRoot:GetAttribute("ArnisPropSourceId")
                incrementInstanceBucket(scene.propInstanceCountByKind, propKind, propSourceId)
                if propKind == "tree" then
                    chunkVegetationInstances += 1
                    scene.vegetationInstanceCount += 1
                    scene.treeInstanceCount += 1
                    incrementInstanceBucket(scene.vegetationInstanceCountByKind, propKind, propSourceId)
                    local species = normalizeBucketValue(propRoot:GetAttribute("ArnisPropSpecies"), "unknown")
                    incrementInstanceBucket(scene.treeInstanceCountBySpecies, species, propSourceId)
                    local connectivityKind = classifyTreeConnectivity(propRoot)
                    incrementTreeConnectivityBucket(scene.treeConnectivityBySpecies, species, connectivityKind)
                    if connectivityKind == "connected" then
                        scene.treeModelsWithConnectedTrunkCanopy += 1
                    elseif connectivityKind == "missing_trunk" then
                        scene.treeModelsMissingTrunk += 1
                    elseif connectivityKind == "missing_canopy" then
                        scene.treeModelsMissingCanopy += 1
                    else
                        scene.treeModelsWithDetachedCanopy += 1
                    end
                elseif propKind == "hedge" or propKind == "shrub" then
                    chunkVegetationInstances += 1
                    scene.vegetationInstanceCount += 1
                    incrementInstanceBucket(scene.vegetationInstanceCountByKind, propKind, propSourceId)
                end
            end
            for _, propRoot in ipairs(ambientPropRoots) do
                chunkAmbientPropInstances += 1
                scene.ambientPropInstanceCount += 1
                incrementInstanceBucket(scene.ambientPropInstanceCountByKind, inferPropKind(propRoot))
            end
        end

        local landuseFolder = child:FindFirstChild("Landuse")
        if landuseFolder then
            local landuseDetailFolder = landuseFolder:FindFirstChild("Detail")
            if landuseDetailFolder then
                for _, detailChild in ipairs(landuseDetailFolder:GetChildren()) do
                    if detailChild:IsA("Model") then
                        local trunks, canopies = collectTreeParts(detailChild)
                        if #trunks > 0 or #canopies > 0 then
                            scene.proceduralTreeInstanceCount += 1
                            local connectivityKind = classifyTreeConnectivity(detailChild)
                            incrementTreeConnectivityBucket(
                                scene.proceduralTreeConnectivityByKind,
                                inferProceduralTreeKind(detailChild),
                                connectivityKind
                            )
                            if connectivityKind == "connected" then
                                scene.proceduralTreeModelsWithConnectedTrunkCanopy += 1
                            elseif connectivityKind == "missing_trunk" then
                                scene.proceduralTreeModelsMissingTrunk += 1
                            elseif connectivityKind == "missing_canopy" then
                                scene.proceduralTreeModelsMissingCanopy += 1
                            else
                                scene.proceduralTreeModelsWithDetachedCanopy += 1
                            end
                        end
                    end
                end
            end
        end

        scene.buildingModelCount += chunkBuildingModels
        scene.roadTaggedPartCount += chunkRoadParts
        if chunkBuildingModels > 0 then
            scene.chunksWithBuildingModels += 1
        end
        if chunkRoadParts > 0 then
            scene.chunksWithRoadGeometry += 1
        end
        if chunkSidewalkSurfaceParts > 0 then
            scene.chunksWithSidewalkSurfaces += 1
        end
        if chunkCrossingSurfaceParts > 0 then
            scene.chunksWithCrossingSurfaces += 1
        end
        if chunkCurbSurfaceParts > 0 then
            scene.chunksWithCurbSurfaces += 1
        end
        if chunkPropInstances > 0 then
            scene.chunksWithProps += 1
        end
        if chunkVegetationInstances > 0 then
            scene.chunksWithVegetation += 1
        end
        if chunkAmbientPropInstances > 0 then
            scene.chunksWithAmbientProps += 1
        end
        if chunkWaterSurfaceParts > 0 then
            scene.chunksWithWaterGeometry += 1
        end
        if chunkRailReceipts > 0 then
            scene.chunksWithRailGeometry += 1
        end
    end

    table.sort(scene.chunkIds)
    return scene
end

return SceneAudit

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local WORLD_ROOT_ATTR = "ArnisMinimapWorldRootName"
local SAMPLE_INTERVAL = 1.5
local NEARBY_BUILDING_RADIUS = 260
local OVERHEAD_ROOF_RADIUS = 220
local OVERHEAD_MIN_DELTA_Y = 12
local RESAMPLE_DISTANCE = 24
local MAX_BUILDING_IDS = 6
local MAX_OVERHEAD_IDS = 6
local GROUND_SAMPLE_HEIGHT = 24
local GROUND_SAMPLE_DEPTH = 256

local lastPayloadJson = nil
local lastSampleAt = 0
local lastSamplePosition = nil
local lastSampleWorldRootName = nil

local function setPlayerAttributeIfChanged(name, nextValue)
    if player:GetAttribute(name) == nextValue then
        return
    end
    player:SetAttribute(name, nextValue)
end

local function getCharacterRootPart()
    local character = player.Character
    if not character then
        return nil
    end
    return character:FindFirstChild("HumanoidRootPart")
end

local function getWorldRoot()
    local worldRootName = Workspace:GetAttribute("ArnisMinimapWorldRootName")
    if type(worldRootName) ~= "string" or worldRootName == "" then
        return nil, nil
    end
    local worldRoot = Workspace:FindFirstChild(worldRootName)
    return worldRoot, worldRootName
end

local function appendLimited(list, value, limit)
    if #list >= limit then
        return
    end
    list[#list + 1] = value
end

local function isDecorativeRoadDetailDescendant(hitInstance)
    local node = hitInstance
    while node and node.Parent do
        if node.Name == "Detail" and node.Parent and node.Parent.Name == "Roads" then
            return true
        end
        node = node.Parent
    end

    return false
end

local function sampleGroundMaterial(rootPart)
    local character = player.Character
    local ignore = {}
    if character then
        ignore[1] = character
    end
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    raycastParams.FilterDescendantsInstances = ignore

    for _ = 1, 8 do
        local origin = rootPart.Position + Vector3.new(0, GROUND_SAMPLE_HEIGHT, 0)
        local direction = Vector3.new(0, -(GROUND_SAMPLE_HEIGHT + GROUND_SAMPLE_DEPTH), 0)
        local rayResult = Workspace:Raycast(origin, direction, raycastParams)
        if not rayResult then
            return nil, nil
        end
        if isDecorativeRoadDetailDescendant(rayResult.Instance) then
            ignore[#ignore + 1] = rayResult.Instance
            raycastParams.FilterDescendantsInstances = ignore
        else
            return tostring(rayResult.Material), rayResult.Instance and rayResult.Instance:GetFullName() or nil
        end
    end

    return nil, nil
end

local function summarizeWorld(rootPart, worldRoot, worldRootName)
    local rootPosition = rootPart.Position
    local nearbyBuildingModels = 0
    local nearbyMergedBuildingMeshParts = 0
    local nearbyRoofParts = 0
    local overheadRoofParts = 0
    local nearestBuildingSourceIds = {}
    local overheadRoofSourceIds = {}
    local nearestBuildingDetails = {}
    local groundMaterial, groundInstance = sampleGroundMaterial(rootPart)

    for _, chunkFolder in ipairs(worldRoot:GetChildren()) do
        local buildingsFolder = chunkFolder:FindFirstChild("Buildings")
        if not buildingsFolder then
            continue
        end

        local mergedMeshes = buildingsFolder:FindFirstChild("MergedMeshes")
        if mergedMeshes then
            for _, descendant in ipairs(mergedMeshes:GetDescendants()) do
                if not descendant:IsA("MeshPart") then
                    continue
                end

                local partOffset = descendant.Position - rootPosition
                local horizontalDistance = Vector2.new(partOffset.X, partOffset.Z).Magnitude
                if horizontalDistance <= NEARBY_BUILDING_RADIUS then
                    nearbyMergedBuildingMeshParts += 1
                end
            end
        end

        for _, model in ipairs(buildingsFolder:GetDescendants()) do
            if not model:IsA("Model") or model:GetAttribute("ArnisImportBuildingHeight") == nil then
                continue
            end

            local sourceId = model:GetAttribute("ArnisImportSourceId")
            if type(sourceId) ~= "string" or sourceId == "" then
                continue
            end
            local roofShape = model:GetAttribute("ArnisImportRoofShape")
            local buildingTopY = model:GetAttribute("ArnisImportBuildingTopY")
            local buildingUsage = model:GetAttribute("ArnisImportBuildingUsage")

            local pivotPosition = model:GetPivot().Position
            local offset = pivotPosition - rootPosition
            local horizontalDistance = Vector2.new(offset.X, offset.Z).Magnitude
            if horizontalDistance > NEARBY_BUILDING_RADIUS then
                continue
            end

            nearbyBuildingModels += 1
            appendLimited(nearestBuildingSourceIds, sourceId, MAX_BUILDING_IDS)
            appendLimited(nearestBuildingDetails, {
                sourceId = sourceId,
                roofShape = roofShape,
                buildingTopY = buildingTopY,
                usage = buildingUsage,
            }, MAX_BUILDING_IDS)

            for _, descendant in ipairs(model:GetDescendants()) do
                if not descendant:IsA("BasePart") then
                    continue
                end

                local nameLower = string.lower(descendant.Name)
                if not string.find(nameLower, "roof", 1, true) then
                    continue
                end

                nearbyRoofParts += 1

                local partOffset = descendant.Position - rootPosition
                local horizontalRoofDistance = Vector2.new(partOffset.X, partOffset.Z).Magnitude
                local verticalDelta = partOffset.Y
                if horizontalRoofDistance <= OVERHEAD_ROOF_RADIUS and verticalDelta >= OVERHEAD_MIN_DELTA_Y then
                    overheadRoofParts += 1
                    appendLimited(overheadRoofSourceIds, sourceId, MAX_OVERHEAD_IDS)
                end
            end
        end
    end

    return {
        worldRootName = worldRootName,
        nearbyBuildingModels = nearbyBuildingModels,
        nearbyMergedBuildingMeshParts = nearbyMergedBuildingMeshParts,
        nearbyRoofParts = nearbyRoofParts,
        overheadRoofParts = overheadRoofParts,
        nearestBuildingSourceIds = nearestBuildingSourceIds,
        nearestBuildingDetails = nearestBuildingDetails,
        overheadRoofSourceIds = overheadRoofSourceIds,
        groundMaterial = groundMaterial,
        groundInstance = groundInstance,
        characterPosition = {
            x = math.round(rootPosition.X * 10) / 10,
            y = math.round(rootPosition.Y * 10) / 10,
            z = math.round(rootPosition.Z * 10) / 10,
        },
    }
end

local function publishWorldTelemetry()
    local rootPart = getCharacterRootPart()
    local worldRoot, worldRootName = getWorldRoot()
    local payload = {
        worldRootName = worldRootName,
        worldRootExists = worldRoot ~= nil,
        nearbyBuildingModels = 0,
        nearbyMergedBuildingMeshParts = 0,
        nearbyRoofParts = 0,
        overheadRoofParts = 0,
        nearestBuildingSourceIds = {},
        overheadRoofSourceIds = {},
        groundMaterial = nil,
        groundInstance = nil,
        characterPosition = nil,
    }

    if rootPart and worldRoot then
        payload = summarizeWorld(rootPart, worldRoot, worldRootName)
        payload.worldRootExists = true
    end

    setPlayerAttributeIfChanged("ArnisClientWorldRootName", payload.worldRootName)
    setPlayerAttributeIfChanged("ArnisClientWorldRootExists", payload.worldRootExists)
    setPlayerAttributeIfChanged("ArnisClientNearbyBuildingModels", payload.nearbyBuildingModels)
    setPlayerAttributeIfChanged("ArnisClientNearbyMergedBuildingMeshParts", payload.nearbyMergedBuildingMeshParts)
    setPlayerAttributeIfChanged("ArnisClientNearbyRoofParts", payload.nearbyRoofParts)
    setPlayerAttributeIfChanged("ArnisClientOverheadRoofParts", payload.overheadRoofParts)
    setPlayerAttributeIfChanged("ArnisClientGroundMaterial", payload.groundMaterial)

    local payloadJson = HttpService:JSONEncode(payload)
    if payloadJson == lastPayloadJson then
        return
    end
    lastPayloadJson = payloadJson
    print("ARNIS_CLIENT_WORLD " .. HttpService:JSONEncode(payload))
end

local function maybeSampleWorldTelemetry()
    local rootPart = getCharacterRootPart()
    local _, worldRootName = getWorldRoot()
    local now = os.clock()
    if now - lastSampleAt < SAMPLE_INTERVAL then
        return
    end
    if rootPart and lastSamplePosition and lastSampleWorldRootName == worldRootName then
        local displacement = (rootPart.Position - lastSamplePosition).Magnitude
        if displacement < RESAMPLE_DISTANCE then
            return
        end
    end
    lastSampleAt = now
    if rootPart then
        lastSamplePosition = rootPart.Position
    end
    lastSampleWorldRootName = worldRootName
    publishWorldTelemetry()
end

player.CharacterAdded:Connect(function()
    lastPayloadJson = nil
    lastSamplePosition = nil
    task.defer(publishWorldTelemetry)
end)

Workspace:GetAttributeChangedSignal(WORLD_ROOT_ATTR):Connect(function()
    lastPayloadJson = nil
    lastSamplePosition = nil
    lastSampleWorldRootName = nil
    publishWorldTelemetry()
end)

RunService.Heartbeat:Connect(function()
    maybeSampleWorldTelemetry()
end)

task.defer(publishWorldTelemetry)

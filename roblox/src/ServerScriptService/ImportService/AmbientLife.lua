local AmbientLife = {}

local CollectionService = game:GetService("CollectionService")

-- Car colors (deterministic from position)
local CAR_COLORS = table.freeze({
    Color3.fromRGB(30, 30, 35), -- black
    Color3.fromRGB(200, 200, 205), -- silver
    Color3.fromRGB(240, 240, 240), -- white
    Color3.fromRGB(50, 60, 100), -- dark blue
    Color3.fromRGB(140, 25, 25), -- dark red
    Color3.fromRGB(60, 80, 60), -- forest green
    Color3.fromRGB(120, 100, 70), -- tan
    Color3.fromRGB(80, 80, 85), -- dark grey
})

local NPC_COUNT_PER_CHUNK = 8 -- keep it light

local NPC_SHIRT_COLORS = table.freeze({
    Color3.fromRGB(60, 80, 140),
    Color3.fromRGB(180, 50, 50),
    Color3.fromRGB(50, 120, 60),
    Color3.fromRGB(200, 180, 100),
    Color3.fromRGB(100, 100, 110),
    Color3.fromRGB(80, 60, 120),
})

local function hashPosition(x, z)
    return math.floor(math.abs(x * 7.3 + z * 13.7)) % 1000
end

local function createParkedCar(parent, position, direction, color)
    local car = Instance.new("Model")
    car.Name = "ParkedCar"

    -- Body
    local body = Instance.new("Part")
    body.Name = "Body"
    body.Size = Vector3.new(6, 2.5, 14)
    body.Material = Enum.Material.SmoothPlastic
    body.Color = color
    body.Anchored = true
    body.CanCollide = true
    body.CastShadow = true
    body.Parent = car

    -- Cabin/roof (slightly narrower, glass-like)
    local cabin = Instance.new("Part")
    cabin.Name = "Cabin"
    cabin.Size = Vector3.new(5.5, 1.8, 7)
    cabin.Material = Enum.Material.Glass
    cabin.Color = Color3.fromRGB(40, 45, 55)
    cabin.Transparency = 0.3
    cabin.Anchored = true
    cabin.CanCollide = false
    cabin.Parent = car

    -- Wheels (4)
    for _, offset in ipairs({
        Vector3.new(-2.8, -1.3, -4.5),
        Vector3.new(2.8, -1.3, -4.5),
        Vector3.new(-2.8, -1.3, 4.5),
        Vector3.new(2.8, -1.3, 4.5),
    }) do
        local wheel = Instance.new("Part")
        wheel.Name = "Wheel"
        wheel.Shape = Enum.PartType.Cylinder
        wheel.Size = Vector3.new(1.5, 2, 2)
        wheel.Material = Enum.Material.SmoothPlastic
        wheel.Color = Color3.fromRGB(25, 25, 30)
        wheel.Anchored = true
        wheel.CanCollide = false
        wheel.Parent = car
        -- Position relative to body
        wheel.CFrame = CFrame.new(position)
            * CFrame.Angles(0, math.atan2(direction.X, direction.Z), 0)
            * CFrame.new(offset)
            * CFrame.Angles(0, 0, math.pi / 2)
    end

    -- Position body and cabin
    local cf = CFrame.lookAt(position, position + direction)
    body.CFrame = cf * CFrame.new(0, 1.5, 0)
    cabin.CFrame = cf * CFrame.new(0, 3.2, -0.5)

    car.PrimaryPart = body
    CollectionService:AddTag(body, "LOD_Detail")
    car.Parent = parent
    return car
end

function AmbientLife.PlaceParkedCars(parent, roads, originStuds)
    if not roads then
        return
    end
    local ox, oy, oz = originStuds.x, originStuds.y, originStuds.z
    local parkingKinds =
        { residential = true, secondary = true, tertiary = true, unclassified = true }
    local carCount = 0
    local MAX_CARS_PER_CHUNK = 30

    for _, road in ipairs(roads) do
        if not parkingKinds[road.kind] then
            continue
        end
        if not road.points or #road.points < 2 then
            continue
        end

        local halfWidth = (road.widthStuds or 10) * 0.5

        for i = 1, #road.points - 1 do
            local p1 = road.points[i]
            local p2 = road.points[i + 1]
            local wx1 = Vector3.new(p1.x + ox, p1.y + oy, p1.z + oz)
            local wx2 = Vector3.new(p2.x + ox, p2.y + oy, p2.z + oz)

            local dir = (wx2 - wx1)
            local segLen = dir.Magnitude
            if segLen < 25 then
                continue
            end
            dir = dir.Unit
            local perp = Vector3.new(-dir.Z, 0, dir.X)

            -- Place cars every ~25 studs, deterministic
            for dist = 15, segLen - 15, 25 do
                if carCount >= MAX_CARS_PER_CHUNK then
                    return
                end

                local hash = hashPosition(wx1.X + dist, wx1.Z + dist)
                if hash % 3 ~= 0 then
                    continue
                end -- only 1/3 of spots filled

                local pos = wx1 + dir * dist + perp * (halfWidth + 4) -- parked alongside
                local surfaceY = (wx1.Y + wx2.Y) * 0.5
                pos = Vector3.new(pos.X, surfaceY + 0.1, pos.Z)

                local colorIdx = (hash % #CAR_COLORS) + 1
                createParkedCar(parent, pos, dir, CAR_COLORS[colorIdx])
                carCount = carCount + 1
            end
        end
    end
end

function AmbientLife.SpawnNPCs(parent, roads, originStuds)
    if not roads then
        return
    end
    local ox, oy, oz = originStuds.x, originStuds.y, originStuds.z
    local npcCount = 0

    for _, road in ipairs(roads) do
        if npcCount >= NPC_COUNT_PER_CHUNK then
            return
        end
        if not road.hasSidewalk and road.sidewalk == "no" then
            continue
        end
        if not road.points or #road.points < 2 then
            continue
        end

        local halfWidth = (road.widthStuds or 10) * 0.5

        -- Pick a deterministic point along this road for an NPC
        local idx = (hashPosition(road.points[1].x, road.points[1].z) % (#road.points - 1)) + 1
        local p1 = road.points[idx]
        local p2 = road.points[math.min(idx + 1, #road.points)]

        local wx = Vector3.new(p1.x + ox, p1.y + oy, p1.z + oz)
        local wx2 = Vector3.new(p2.x + ox, p2.y + oy, p2.z + oz)
        local dir = (wx2 - wx).Unit
        local perp = Vector3.new(-dir.Z, 0, dir.X)

        -- Place on sidewalk
        local npcPos = wx + perp * (halfWidth + 3) + Vector3.new(0, 3, 0)

        -- Create simple NPC (no Humanoid for performance)
        local npc = Instance.new("Model")
        npc.Name = "NPC_" .. npcCount

        -- Torso
        local torso = Instance.new("Part")
        torso.Name = "Torso"
        torso.Size = Vector3.new(2, 2.5, 1)
        torso.Material = Enum.Material.SmoothPlastic
        torso.Color = NPC_SHIRT_COLORS[(npcCount % #NPC_SHIRT_COLORS) + 1]
        torso.CFrame = CFrame.new(npcPos)
        torso.Anchored = true
        torso.CanCollide = false
        torso.Parent = npc

        -- Head
        local head = Instance.new("Part")
        head.Name = "Head"
        head.Shape = Enum.PartType.Ball
        head.Size = Vector3.new(1.5, 1.5, 1.5)
        head.Material = Enum.Material.SmoothPlastic
        head.Color = Color3.fromRGB(210, 180, 150) -- skin tone
        head.CFrame = CFrame.new(npcPos + Vector3.new(0, 2, 0))
        head.Anchored = true
        head.CanCollide = false
        head.Parent = npc

        -- Legs
        for _, legX in ipairs({ -0.5, 0.5 }) do
            local leg = Instance.new("Part")
            leg.Name = "Leg"
            leg.Size = Vector3.new(0.8, 2.5, 0.8)
            leg.Material = Enum.Material.SmoothPlastic
            leg.Color = Color3.fromRGB(40, 45, 60) -- dark pants
            leg.CFrame = CFrame.new(npcPos + Vector3.new(legX, -2.5, 0))
            leg.Anchored = true
            leg.CanCollide = false
            leg.Parent = npc
        end

        npc.PrimaryPart = torso
        CollectionService:AddTag(torso, "LOD_Detail")
        npc.Parent = parent
        npcCount = npcCount + 1
    end
end

return AmbientLife

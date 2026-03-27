return function()
    local CollectionService = game:GetService("CollectionService")
    local Lighting = game:GetService("Lighting")
    local Workspace = game:GetService("Workspace")
    local DayNightCycle = require(script.Parent.Parent.ImportService.DayNightCycle)
    local Assert = require(script.Parent.Assert)

    local worldRoot = Instance.new("Folder")
    worldRoot.Name = "DayNightCycleSpecWorld"
    worldRoot.Parent = Workspace

    local chunkFolder = Instance.new("Folder")
    chunkFolder.Name = "day_night_chunk"
    chunkFolder.Parent = worldRoot

    local detailFolder = Instance.new("Folder")
    detailFolder.Name = "Detail"
    detailFolder:SetAttribute("ArnisLodGroupKind", "detail")
    CollectionService:AddTag(detailFolder, "LOD_DetailGroup")
    detailFolder.Parent = chunkFolder

    local glass = Instance.new("Part")
    glass.Name = "FacadeBand"
    glass.Material = Enum.Material.Glass
    glass.Color = Color3.fromRGB(40, 50, 70)
    glass.Transparency = 0.35
    glass:SetAttribute("BaseTransparency", 0.35)
    glass.Parent = detailFolder

    local lightHead = Instance.new("Part")
    lightHead.Name = "StreetLightHead"
    CollectionService:AddTag(lightHead, "StreetLight")
    lightHead.Parent = detailFolder

    local pointLight = Instance.new("PointLight")
    pointLight.Enabled = false
    pointLight.Parent = lightHead

    local ChunkLoader = require(script.Parent.Parent.ImportService.ChunkLoader)
    ChunkLoader.Clear()
    ChunkLoader.RegisterChunk("day_night_chunk", chunkFolder, {
        id = "day_night_chunk",
        originStuds = { x = 0, y = 0, z = 0 },
    }, {
        worldRootName = worldRoot.Name,
    })

    local originalClockTime = Lighting.ClockTime
    DayNightCycle.SetTime(22)
    Assert.near(glass.Transparency, 0.1, 1e-6, "expected grouped glass detail to glow at night")
    Assert.truthy(pointLight.Enabled, "expected street lights enabled at night")

    DayNightCycle.SetTime(12)
    Assert.near(glass.Transparency, 0.35, 1e-6, "expected grouped glass detail to restore base transparency by day")
    Assert.falsy(pointLight.Enabled, "expected street lights disabled by day")

    Lighting.ClockTime = originalClockTime
    ChunkLoader.Clear()
    worldRoot:Destroy()
end

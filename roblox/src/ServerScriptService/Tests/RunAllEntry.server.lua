local RunService = game:GetService("RunService")
local RunAllConfig = require(script.Parent.RunAllConfig)

if not RunService:IsStudio() then
    return
end

local isPlayMode = RunService:IsRunning()

if isPlayMode then
    if not RunAllConfig.runInPlayMode then
        return
    end
elseif not RunAllConfig.runInEditMode then
    return
end

local RunAll = require(script.Parent.RunAll)
workspace:SetAttribute("VertigoSyncEditPreviewSuspended", true)
workspace:SetAttribute("VertigoSyncEditPreviewSuspendReason", "arnis_tests")
local ok, err = pcall(function()
    RunAll.run({
        specNameFilter = RunAllConfig.specNameFilter,
    })
end)
workspace:SetAttribute("VertigoSyncEditPreviewSuspended", false)
workspace:SetAttribute("VertigoSyncEditPreviewSuspendReason", "")
if not ok then
    error(err)
end

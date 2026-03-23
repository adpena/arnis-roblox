local RunService = game:GetService("RunService")

local RUN_IN_EDIT_MODE = true
local RUN_IN_PLAY_MODE = false

if not RunService:IsStudio() then
    return
end

local isPlayMode = RunService:IsRunning()

if isPlayMode then
    if not RUN_IN_PLAY_MODE then
        return
    end
elseif not RUN_IN_EDIT_MODE then
    return
end

local RunAll = require(script.Parent.RunAll)
workspace:SetAttribute("VertigoSyncEditPreviewSuspended", true)
workspace:SetAttribute("VertigoSyncEditPreviewSuspendReason", "arnis_tests")
local ok, err = pcall(function()
    RunAll.run()
end)
workspace:SetAttribute("VertigoSyncEditPreviewSuspended", false)
workspace:SetAttribute("VertigoSyncEditPreviewSuspendReason", "")
if not ok then
    error(err)
end

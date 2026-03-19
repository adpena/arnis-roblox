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
RunAll.run()

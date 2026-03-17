local toolbar = plugin:CreateToolbar("Arnis Roblox")
local importButton = toolbar:CreateButton(
    "Import Sample",
    "Import the sample chunk manifest into Workspace.GeneratedWorld",
    ""
)
local testButton = toolbar:CreateButton(
    "Run Smoke Tests",
    "Run the scaffold smoke tests",
    ""
)

local Controller = require(script.Controller)

importButton.Click:Connect(function()
    Controller.importSample()
end)

testButton.Click:Connect(function()
    Controller.runSmokeTests()
end)

return function()
    local Workspace = game:GetService("Workspace")
    local Assert = require(script.Parent.Assert)
    local SceneAudit = require(script.Parent.Parent.ImportService.SceneAudit)

    local worldRoot = Instance.new("Folder")
    worldRoot.Name = "GeneratedWorld_SceneAudit_PalmFrond"
    worldRoot.Parent = Workspace

    local chunkFolder = Instance.new("Folder")
    chunkFolder.Name = "0_0"
    chunkFolder.Parent = worldRoot

    local propsFolder = Instance.new("Folder")
    propsFolder.Name = "Props"
    propsFolder.Parent = chunkFolder

    local detailFolder = Instance.new("Folder")
    detailFolder.Name = "Detail"
    detailFolder.Parent = propsFolder

    local palmTree = Instance.new("Model")
    palmTree.Name = "TreePalm"
    palmTree:SetAttribute("ArnisPropKind", "tree")
    palmTree:SetAttribute("ArnisPropSpecies", "palm")
    palmTree:SetAttribute("ArnisPropSourceId", "tree_palm_1")
    palmTree.Parent = detailFolder

    local trunk = Instance.new("Part")
    trunk.Name = "Trunk"
    trunk.Size = Vector3.new(2, 10, 2)
    trunk.CFrame = CFrame.new(0, 5, 0)
    trunk.Parent = palmTree

    local frond = Instance.new("Part")
    frond.Name = "FrondMain"
    frond.Size = Vector3.new(10, 2, 10)
    frond.CFrame = CFrame.new(0, 10.5, 0)
    frond.Parent = palmTree

    local summary = SceneAudit.summarizeWorld(worldRoot)

    Assert.equal(summary.treeModelsWithConnectedTrunkCanopy, 1, "expected palm fronds to count as canopy")
    Assert.equal(summary.treeModelsMissingCanopy, 0, "expected no missing-canopy palm trees")
    Assert.equal(
        summary.treeConnectivityBySpecies.palm.connectedCount,
        1,
        "expected palm connectivity to be classified as connected"
    )
    Assert.equal(
        summary.treeConnectivityBySpecies.palm.missingCanopyCount,
        0,
        "expected palm connectivity to avoid missing-canopy classification"
    )

    worldRoot:Destroy()
end

return function()
    local Workspace = game:GetService("Workspace")
    local ImportService = require(script.Parent.Parent.ImportService)
    local ManifestLoader = require(script.Parent.Parent.ImportService.ManifestLoader)
    local Assert = require(script.Parent.Assert)

    local manifest = ManifestLoader.LoadNamedSample("SampleManifest")

    local stats = ImportService.ImportManifest(manifest, {
        clearFirst = true,
        worldRootName = "GeneratedWorld_Test",
    })

    Assert.equal(stats.chunksImported, 1, "expected one imported chunk")

    local worldRoot = Workspace:FindFirstChild("GeneratedWorld_Test")
    Assert.truthy(worldRoot, "expected GeneratedWorld_Test to exist")

    local chunkFolder = worldRoot:FindFirstChild("0_0")
    Assert.truthy(chunkFolder, "expected chunk folder")

    local chunkFolderRef = chunkFolder
    local repeatStats = ImportService.ImportManifest(manifest, {
        clearFirst = false,
        worldRootName = "GeneratedWorld_Test",
    })
    Assert.equal(repeatStats.chunksImported, 1, "expected one imported chunk on repeat import")

    local chunkFolders = {}
    for _, child in ipairs(worldRoot:GetChildren()) do
        if child.Name == "0_0" then
            chunkFolders[#chunkFolders + 1] = child
        end
    end
    Assert.equal(
        #chunkFolders,
        1,
        "expected repeat import to keep a single authoritative chunk folder"
    )
    Assert.equal(
        chunkFolders[1],
        chunkFolderRef,
        "expected repeat import to preserve chunk folder instance"
    )

    worldRoot:Destroy()

    local profiledChunk = manifest.chunks[1]
    local chunkProfiles = {}
    local profiledRootName = "GeneratedWorld_Test_Profiled"
    local _chunkFolder, artifactCount = ImportService.ImportChunk(profiledChunk, {
        worldRootName = profiledRootName,
        onChunkProfile = function(profile)
            table.insert(chunkProfiles, profile)
        end,
    })

    Assert.equal(#chunkProfiles, 1, "expected ImportChunk to emit one profile callback")
    Assert.equal(
        chunkProfiles[1].chunkId,
        profiledChunk.id,
        "expected chunk profile to identify the chunk"
    )
    Assert.equal(
        chunkProfiles[1].artifactCount,
        artifactCount,
        "expected chunk profile to include artifact count"
    )
    Assert.truthy(
        type(chunkProfiles[1].totalMs) == "number",
        "expected chunk profile totalMs number"
    )
    Assert.truthy(
        type(chunkProfiles[1].roadsMs) == "number",
        "expected chunk profile roadsMs number"
    )
    Assert.truthy(
        type(chunkProfiles[1].roadsSurfaceMs) == "number",
        "expected chunk profile roadsSurfaceMs number"
    )
    Assert.truthy(
        type(chunkProfiles[1].roadSurfaceAccumulatorCount) == "number",
        "expected chunk profile roadSurfaceAccumulatorCount number"
    )
    Assert.truthy(
        type(chunkProfiles[1].roadSurfaceMeshPartCount) == "number",
        "expected chunk profile roadSurfaceMeshPartCount number"
    )
    Assert.truthy(
        type(chunkProfiles[1].roadSurfaceSegmentCount) == "number",
        "expected chunk profile roadSurfaceSegmentCount number"
    )
    Assert.truthy(
        type(chunkProfiles[1].roadSurfaceVertexCount) == "number",
        "expected chunk profile roadSurfaceVertexCount number"
    )
    Assert.truthy(
        type(chunkProfiles[1].roadSurfaceTriangleCount) == "number",
        "expected chunk profile roadSurfaceTriangleCount number"
    )
    Assert.truthy(
        type(chunkProfiles[1].roadSurfaceMeshCreateMs) == "number",
        "expected chunk profile roadSurfaceMeshCreateMs number"
    )
    Assert.truthy(
        type(chunkProfiles[1].buildingMeshPartCount) == "number",
        "expected chunk profile buildingMeshPartCount number"
    )
    Assert.truthy(
        type(chunkProfiles[1].buildingMeshVertexCount) == "number",
        "expected chunk profile buildingMeshVertexCount number"
    )
    Assert.truthy(
        type(chunkProfiles[1].buildingMeshTriangleCount) == "number",
        "expected chunk profile buildingMeshTriangleCount number"
    )
    Assert.truthy(
        type(chunkProfiles[1].buildingMeshCreateMs) == "number",
        "expected chunk profile buildingMeshCreateMs number"
    )
    Assert.truthy(
        type(chunkProfiles[1].roadsDecorationMs) == "number",
        "expected chunk profile roadsDecorationMs number"
    )
    Assert.truthy(
        type(chunkProfiles[1].buildingRoofMeshPartCount) == "number",
        "expected chunk profile buildingRoofMeshPartCount number"
    )
    Assert.truthy(
        type(chunkProfiles[1].buildingsMs) == "number",
        "expected chunk profile buildingsMs number"
    )
    Assert.truthy(
        type(chunkProfiles[1].landusePlanMs) == "number",
        "expected chunk profile landusePlanMs number"
    )
    Assert.truthy(
        type(chunkProfiles[1].landuseExecuteMs) == "number",
        "expected chunk profile landuseExecuteMs number"
    )
    Assert.truthy(
        type(chunkProfiles[1].landuseTerrainFillMs) == "number",
        "expected chunk profile landuseTerrainFillMs number"
    )
    Assert.truthy(
        type(chunkProfiles[1].landuseDetailMs) == "number",
        "expected chunk profile landuseDetailMs number"
    )
    Assert.truthy(
        type(chunkProfiles[1].landuseCellCount) == "number",
        "expected chunk profile landuseCellCount number"
    )
    Assert.truthy(
        type(chunkProfiles[1].landuseRectCount) == "number",
        "expected chunk profile landuseRectCount number"
    )
    Assert.truthy(
        type(chunkProfiles[1].landuseDetailInstanceCount) == "number",
        "expected chunk profile landuseDetailInstanceCount number"
    )
    Assert.truthy(
        type(chunkProfiles[1].propFeatureCount) == "number",
        "expected chunk profile propFeatureCount number"
    )
    Assert.truthy(
        type(chunkProfiles[1].propKindCount) == "number",
        "expected chunk profile propKindCount number"
    )
    Assert.truthy(
        chunkProfiles[1].propTopKind1 == nil or type(chunkProfiles[1].propTopKind1) == "string",
        "expected chunk profile propTopKind1 string or nil"
    )
    Assert.truthy(
        type(chunkProfiles[1].propTopKind1Count) == "number",
        "expected chunk profile propTopKind1Count number"
    )
    Assert.truthy(
        type(chunkProfiles[1].propTopKind1Ms) == "number",
        "expected chunk profile propTopKind1Ms number"
    )
    Assert.truthy(
        chunkProfiles[1].propTopKind2 == nil or type(chunkProfiles[1].propTopKind2) == "string",
        "expected chunk profile propTopKind2 string or nil"
    )
    Assert.truthy(
        type(chunkProfiles[1].propTopKind2Count) == "number",
        "expected chunk profile propTopKind2Count number"
    )
    Assert.truthy(
        type(chunkProfiles[1].propTopKind2Ms) == "number",
        "expected chunk profile propTopKind2Ms number"
    )
    Assert.truthy(
        chunkProfiles[1].propTopKind3 == nil or type(chunkProfiles[1].propTopKind3) == "string",
        "expected chunk profile propTopKind3 string or nil"
    )
    Assert.truthy(
        type(chunkProfiles[1].propTopKind3Count) == "number",
        "expected chunk profile propTopKind3Count number"
    )
    Assert.truthy(
        type(chunkProfiles[1].propTopKind3Ms) == "number",
        "expected chunk profile propTopKind3Ms number"
    )

    local profiledRoot = Workspace:FindFirstChild(profiledRootName)
    if profiledRoot then
        profiledRoot:Destroy()
    end
end

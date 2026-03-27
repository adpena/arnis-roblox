return function()
    local CollectionService = game:GetService("CollectionService")
    local Workspace = game:GetService("Workspace")
    local Assert = require(script.Parent.Assert)
    local SceneAudit = require(script.Parent.Parent.ImportService.SceneAudit)

    local worldRoot = Instance.new("Folder")
    worldRoot.Name = "GeneratedWorld_SceneAudit"
    worldRoot.Parent = Workspace

    local chunkFolder = Instance.new("Folder")
    chunkFolder.Name = "0_0"
    chunkFolder.Parent = worldRoot

    local buildingsFolder = Instance.new("Folder")
    buildingsFolder.Name = "Buildings"
    buildingsFolder.Parent = chunkFolder

    local directShellBuilding = Instance.new("Model")
    directShellBuilding.Name = "direct_shell"
    directShellBuilding:SetAttribute("ArnisImportBuildingHeight", 24)
    directShellBuilding:SetAttribute("ArnisImportSourceId", "direct_shell")
    directShellBuilding:SetAttribute("ArnisImportBuildingUsage", "office")
    directShellBuilding:SetAttribute("ArnisImportRoofShape", "flat")
    directShellBuilding:SetAttribute("ArnisImportWallMaterial", "Concrete")
    directShellBuilding:SetAttribute("ArnisImportRoofMaterial", "Slate")
    directShellBuilding.Parent = buildingsFolder

    local shellFolder = Instance.new("Folder")
    shellFolder.Name = "Shell"
    shellFolder.Parent = directShellBuilding

    local wall = Instance.new("Part")
    wall.Name = "WallSegment"
    wall.Parent = shellFolder

    local roof = Instance.new("Part")
    roof.Name = "direct_shell_roof"
    roof.Parent = shellFolder

    local roofClosure = Instance.new("Part")
    roofClosure.Name = "direct_shell_roof_closure"
    roofClosure.Parent = shellFolder

    local directDetail = Instance.new("Folder")
    directDetail.Name = "Detail"
    directDetail.Parent = directShellBuilding

    local facade = Instance.new("Part")
    facade.Name = "direct_shell_facade_1_1"
    facade.Parent = directDetail

    local mergedShellBuilding = Instance.new("Model")
    mergedShellBuilding.Name = "merged_shell"
    mergedShellBuilding:SetAttribute("ArnisImportBuildingHeight", 18)
    mergedShellBuilding:SetAttribute("ArnisImportSourceId", "merged_shell")
    mergedShellBuilding:SetAttribute("ArnisImportBuildingUsage", "university")
    mergedShellBuilding:SetAttribute("ArnisImportRoofShape", "gabled")
    mergedShellBuilding:SetAttribute("ArnisImportWallMaterial", "Brick")
    mergedShellBuilding:SetAttribute("ArnisImportRoofMaterial", "Brick")
    mergedShellBuilding.Parent = buildingsFolder

    local mergedDetail = Instance.new("Folder")
    mergedDetail.Name = "Detail"
    mergedDetail.Parent = mergedShellBuilding

    local closureOnlyBuilding = Instance.new("Model")
    closureOnlyBuilding.Name = "closure_only_hipped"
    closureOnlyBuilding:SetAttribute("ArnisImportBuildingHeight", 20)
    closureOnlyBuilding:SetAttribute("ArnisImportSourceId", "closure_only_hipped")
    closureOnlyBuilding:SetAttribute("ArnisImportBuildingUsage", "civic")
    closureOnlyBuilding:SetAttribute("ArnisImportRoofShape", "hipped")
    closureOnlyBuilding:SetAttribute("ArnisImportWallMaterial", "Limestone")
    closureOnlyBuilding:SetAttribute("ArnisImportRoofMaterial", "Metal")
    closureOnlyBuilding.Parent = buildingsFolder

    local closureOnlyShell = Instance.new("Folder")
    closureOnlyShell.Name = "Shell"
    closureOnlyShell.Parent = closureOnlyBuilding

    local closureOnlyRoof = Instance.new("Part")
    closureOnlyRoof.Name = "closure_only_hipped_roof_closure"
    closureOnlyRoof.Parent = closureOnlyShell

    local mergedFlatRoofBuilding = Instance.new("Model")
    mergedFlatRoofBuilding.Name = "merged_flat_roof"
    mergedFlatRoofBuilding:SetAttribute("ArnisImportBuildingHeight", 22)
    mergedFlatRoofBuilding:SetAttribute("ArnisImportSourceId", "merged_flat_roof")
    mergedFlatRoofBuilding:SetAttribute("ArnisImportBuildingUsage", "commercial")
    mergedFlatRoofBuilding:SetAttribute("ArnisImportRoofShape", "flat")
    mergedFlatRoofBuilding:SetAttribute("ArnisImportHasMergedRoofGeometry", true)
    mergedFlatRoofBuilding:SetAttribute("ArnisImportWallMaterial", "Glass")
    mergedFlatRoofBuilding:SetAttribute("ArnisImportRoofMaterial", "Slate")
    mergedFlatRoofBuilding.Parent = buildingsFolder

    local mergedFlatShellFolder = Instance.new("Folder")
    mergedFlatShellFolder.Name = "Shell"
    mergedFlatShellFolder.Parent = mergedFlatRoofBuilding

    local mergedFlatShellMesh = Instance.new("MeshPart")
    mergedFlatShellMesh.Name = "merged_flat_shell_mesh"
    mergedFlatShellMesh.Parent = mergedFlatShellFolder

    local mergedMeshes = Instance.new("Folder")
    mergedMeshes.Name = "MergedMeshes"
    mergedMeshes.Parent = buildingsFolder

    local mergedMesh = Instance.new("MeshPart")
    mergedMesh.Name = "Concrete:merged"
    mergedMesh.Parent = mergedMeshes

    local roadsFolder = Instance.new("Folder")
    roadsFolder.Name = "Roads"
    roadsFolder.Parent = chunkFolder

    local roadDeck = Instance.new("Part")
    roadDeck.Name = "RoadDeck"
    roadDeck.Parent = roadsFolder
    CollectionService:AddTag(roadDeck, "Road")
    roadDeck:SetAttribute("ArnisRoadSurfaceRole", "road")
    roadDeck:SetAttribute("ArnisRoadKind", "secondary")
    roadDeck:SetAttribute("ArnisRoadSourceCount", 3)
    roadDeck:SetAttribute("ArnisRoadSourceIds", "road_1\nroad_2\nroad_3")

    local sidewalkSurface = Instance.new("Part")
    sidewalkSurface.Name = "SidewalkSurface"
    sidewalkSurface.Parent = roadsFolder
    sidewalkSurface:SetAttribute("ArnisRoadSurfaceRole", "sidewalk")
    sidewalkSurface:SetAttribute("ArnisRoadKind", "footway")
    sidewalkSurface:SetAttribute("ArnisRoadSubkind", "sidewalk")
    sidewalkSurface:SetAttribute("ArnisRoadSourceCount", 2)
    sidewalkSurface:SetAttribute("ArnisRoadSourceIds", "road_4\nroad_5")

    local crossingSurface = Instance.new("Part")
    crossingSurface.Name = "CrossingSurface"
    crossingSurface.Parent = roadsFolder
    crossingSurface:SetAttribute("ArnisRoadSurfaceRole", "crossing")
    crossingSurface:SetAttribute("ArnisRoadKind", "footway")
    crossingSurface:SetAttribute("ArnisRoadSubkind", "crossing")
    crossingSurface:SetAttribute("ArnisRoadSourceCount", 1)
    crossingSurface:SetAttribute("ArnisRoadSourceIds", "road_6")

    local curbSurface = Instance.new("Part")
    curbSurface.Name = "CurbSurface"
    curbSurface.Parent = roadsFolder
    curbSurface:SetAttribute("ArnisRoadSurfaceRole", "curb")
    curbSurface:SetAttribute("ArnisRoadKind", "secondary")
    curbSurface:SetAttribute("ArnisRoadSubkind", "curb")
    curbSurface:SetAttribute("ArnisRoadSourceCount", 2)
    curbSurface:SetAttribute("ArnisRoadSourceIds", "road_7\nroad_8")

    local railsFolder = Instance.new("Folder")
    railsFolder.Name = "Rails"
    railsFolder.Parent = chunkFolder

    local railRecordA = Instance.new("Configuration")
    railRecordA.Name = "RailAudit_osm_rail_1"
    railRecordA:SetAttribute("ArnisRailAuditRecord", true)
    railRecordA:SetAttribute("ArnisRailKind", "rail")
    railRecordA:SetAttribute("ArnisRailSourceId", "osm_rail_1")
    railRecordA.Parent = railsFolder

    local railRecordB = Instance.new("Configuration")
    railRecordB.Name = "RailAudit_osm_tram_1"
    railRecordB:SetAttribute("ArnisRailAuditRecord", true)
    railRecordB:SetAttribute("ArnisRailKind", "tram")
    railRecordB:SetAttribute("ArnisRailSourceId", "osm_tram_1")
    railRecordB.Parent = railsFolder

    local roadDetail = Instance.new("Folder")
    roadDetail.Name = "Detail"
    roadDetail.Parent = roadsFolder

    local crosswalkStripe = Instance.new("Part")
    crosswalkStripe.Name = "CrosswalkStripe"
    crosswalkStripe.Parent = roadDetail

    local propsFolder = Instance.new("Folder")
    propsFolder.Name = "Props"
    propsFolder.Parent = chunkFolder

    local propsDetailFolder = Instance.new("Folder")
    propsDetailFolder.Name = "Detail"
    propsDetailFolder.Parent = propsFolder

    local canopyOnlyTree = Instance.new("Model")
    canopyOnlyTree.Name = "TreeOak"
    canopyOnlyTree:SetAttribute("ArnisPropKind", "tree")
    canopyOnlyTree:SetAttribute("ArnisPropSpecies", "oak")
    canopyOnlyTree:SetAttribute("ArnisPropSourceId", "tree_oak_1")
    canopyOnlyTree.Parent = propsDetailFolder

    local canopyOnlyPart = Instance.new("Part")
    canopyOnlyPart.Name = "Canopy"
    canopyOnlyPart.Size = Vector3.new(8, 6, 8)
    canopyOnlyPart.CFrame = CFrame.new(0, 12, 0)
    canopyOnlyPart.Parent = canopyOnlyTree

    local connectedTree = Instance.new("Model")
    connectedTree.Name = "TreeElm"
    connectedTree:SetAttribute("ArnisPropKind", "tree")
    connectedTree:SetAttribute("ArnisPropSpecies", "elm")
    connectedTree:SetAttribute("ArnisPropSourceId", "tree_elm_1")
    connectedTree.Parent = propsDetailFolder

    local connectedTrunk = Instance.new("Part")
    connectedTrunk.Name = "TrunkUpper"
    connectedTrunk.Size = Vector3.new(2, 10, 2)
    connectedTrunk.CFrame = CFrame.new(20, 5, 0)
    connectedTrunk.Parent = connectedTree

    local connectedCanopy = Instance.new("Part")
    connectedCanopy.Name = "CanopyMain"
    connectedCanopy.Size = Vector3.new(10, 8, 10)
    connectedCanopy.CFrame = CFrame.new(20, 12.5, 0)
    connectedCanopy.Parent = connectedTree

    local detachedTree = Instance.new("Model")
    detachedTree.Name = "TreeCedar"
    detachedTree:SetAttribute("ArnisPropKind", "tree")
    detachedTree:SetAttribute("ArnisPropSpecies", "cedar")
    detachedTree:SetAttribute("ArnisPropSourceId", "tree_cedar_1")
    detachedTree.Parent = propsDetailFolder

    local detachedTrunk = Instance.new("Part")
    detachedTrunk.Name = "Trunk"
    detachedTrunk.Size = Vector3.new(2, 8, 2)
    detachedTrunk.CFrame = CFrame.new(40, 4, 0)
    detachedTrunk.Parent = detachedTree

    local detachedCanopy = Instance.new("Part")
    detachedCanopy.Name = "Canopy"
    detachedCanopy.Size = Vector3.new(8, 6, 8)
    detachedCanopy.CFrame = CFrame.new(40, 18, 0)
    detachedCanopy.Parent = detachedTree

    local fountainPart = Instance.new("Part")
    fountainPart.Name = "Fountain"
    fountainPart:SetAttribute("ArnisPropKind", "fountain")
    fountainPart:SetAttribute("ArnisPropSourceId", "fountain_1")
    fountainPart.Parent = propsDetailFolder

    local parkedCar = Instance.new("Model")
    parkedCar.Name = "ParkedCar"
    parkedCar.Parent = propsFolder

    local carBody = Instance.new("Part")
    carBody.Name = "Body"
    carBody.Parent = parkedCar

    local landuseFolder = Instance.new("Folder")
    landuseFolder.Name = "Landuse"
    landuseFolder.Parent = chunkFolder

    local landuseDetailFolder = Instance.new("Folder")
    landuseDetailFolder.Name = "Detail"
    landuseDetailFolder.Parent = landuseFolder

    local proceduralTree = Instance.new("Model")
    proceduralTree.Name = "park_tree"
    proceduralTree.Parent = landuseDetailFolder

    local proceduralTrunk = Instance.new("Part")
    proceduralTrunk.Name = "Trunk"
    proceduralTrunk.Size = Vector3.new(1, 8, 1)
    proceduralTrunk.CFrame = CFrame.new(80, 4, 0)
    proceduralTrunk.Parent = proceduralTree

    local proceduralCanopy = Instance.new("Part")
    proceduralCanopy.Name = "Canopy"
    proceduralCanopy.Size = Vector3.new(8, 6, 8)
    proceduralCanopy.CFrame = CFrame.new(80, 10, 0)
    proceduralCanopy.Parent = proceduralTree

    local summary = SceneAudit.summarizeWorld(worldRoot)

    Assert.equal(summary.chunkCount, 1, "expected one chunk in scene summary")
    Assert.equal(summary.buildingModelCount, 4, "expected four building models")
    Assert.equal(summary.buildingShellPartCount, 5, "expected direct shell parts plus one shell mesh part")
    Assert.equal(summary.buildingRoofPartCount, 1, "expected one direct roof part")
    Assert.equal(summary.buildingModelsWithRoofClosureDeck, 2, "expected two buildings with roof closure decks")
    Assert.equal(summary.buildingModelsWithRoof, 2, "expected two buildings with roof geometry")
    Assert.equal(summary.buildingModelsWithoutRoof, 2, "expected two buildings without roof geometry")
    Assert.equal(summary.buildingModelsWithDirectRoof, 1, "expected one building with direct roof parts")
    Assert.equal(
        summary.buildingModelsWithMergedRoofOnly,
        1,
        "expected one building that relies on merged roof geometry only"
    )
    Assert.equal(summary.buildingModelsWithNoRoofEvidence, 2, "expected two buildings with no direct roof evidence")
    Assert.equal(
        summary.buildingRoofCoverageByUsage.office.withRoofCount,
        1,
        "expected office roof coverage to count the roofed building"
    )
    Assert.equal(
        summary.buildingRoofCoverageByUsage.office.directRoofCount,
        1,
        "expected office roof coverage to count the direct roof building"
    )
    Assert.equal(
        summary.buildingRoofCoverageByUsage.office.closureDeckCount,
        1,
        "expected office roof coverage to count the closure deck"
    )
    Assert.equal(
        summary.buildingRoofCoverageByUsage.civic.withoutRoofCount,
        1,
        "expected closure-only shaped roofs to remain classified as lacking direct roof evidence"
    )
    Assert.equal(
        summary.buildingRoofCoverageByUsage.civic.closureDeckCount,
        1,
        "expected closure-only shaped roofs to still report their closure deck"
    )
    Assert.equal(
        summary.buildingRoofCoverageByUsage.commercial.withRoofCount,
        1,
        "expected commercial roof coverage to count the merged flat roof building"
    )
    Assert.equal(
        summary.buildingRoofCoverageByUsage.commercial.mergedRoofOnlyCount,
        1,
        "expected commercial roof coverage to count the merged-only roof building"
    )
    Assert.equal(
        summary.buildingRoofCoverageByUsage.university.withoutRoofCount,
        1,
        "expected university roof coverage to count the roofless building"
    )
    Assert.equal(
        summary.buildingRoofCoverageByUsage.university.noRoofEvidenceCount,
        1,
        "expected university roof coverage to count the roofless building as no-evidence"
    )
    Assert.equal(
        summary.buildingRoofCoverageByShape.flat.withRoofCount,
        2,
        "expected flat roof coverage to count both explicit and merged roof geometry"
    )
    Assert.equal(
        summary.buildingRoofCoverageByShape.flat.directRoofCount,
        1,
        "expected flat roof coverage to count one direct roof"
    )
    Assert.equal(
        summary.buildingRoofCoverageByShape.flat.closureDeckCount,
        1,
        "expected flat roof coverage to count one closure deck"
    )
    Assert.equal(
        summary.buildingRoofCoverageByShape.flat.mergedRoofOnlyCount,
        1,
        "expected flat roof coverage to count one merged-only roof"
    )
    Assert.equal(
        summary.buildingRoofCoverageByShape.gabled.withoutRoofCount,
        1,
        "expected gabled roof coverage to count the roofless building"
    )
    Assert.equal(
        summary.buildingRoofCoverageByShape.gabled.noRoofEvidenceCount,
        1,
        "expected gabled roof coverage to count the roofless building as no-evidence"
    )
    Assert.equal(
        summary.buildingRoofCoverageByShape.hipped.withoutRoofCount,
        1,
        "expected hipped closure-only coverage to stay out of direct roof counts"
    )
    Assert.equal(
        summary.buildingRoofCoverageByShape.hipped.closureDeckCount,
        1,
        "expected hipped closure-only coverage to preserve closure-deck evidence"
    )
    Assert.equal(summary.buildingFacadePartCount, 1, "expected one facade part")
    Assert.equal(summary.buildingModelsWithDirectShell, 3, "expected three buildings with direct shell geometry")
    Assert.equal(summary.buildingModelsMissingDirectShell, 1, "expected one building relying on merged geometry")
    Assert.equal(summary.buildingShellMeshPartCount, 1, "expected one shell mesh part supporting merged shell geometry")
    Assert.equal(summary.mergedBuildingMeshPartCount, 1, "expected one merged building mesh part")
    Assert.equal(
        summary.buildingModelCountByWallMaterial.concrete.buildingModelCount,
        1,
        "expected one concrete wall material building"
    )
    Assert.equal(
        summary.buildingModelCountByWallMaterial.concrete.sourceIds[1],
        "direct_shell",
        "expected concrete wall material source id"
    )
    Assert.equal(
        summary.buildingModelCountByWallMaterial.glass.buildingModelCount,
        1,
        "expected one glass wall material building"
    )
    Assert.equal(
        summary.buildingModelCountByRoofMaterial.slate.buildingModelCount,
        2,
        "expected two slate roof material buildings"
    )
    Assert.equal(
        summary.buildingModelCountByRoofMaterial.slate.sourceIds[2],
        "merged_flat_roof",
        "expected second slate roof material source id"
    )
    Assert.equal(
        summary.buildingModelCountByRoofMaterial.metal.buildingModelCount,
        1,
        "expected one metal roof material building"
    )
    Assert.equal(summary.roadTaggedPartCount, 1, "expected one tagged road part")
    Assert.equal(summary.roadSurfacePartCount, 1, "expected one explicit road surface part")
    Assert.equal(summary.sidewalkSurfacePartCount, 1, "expected one explicit sidewalk surface part")
    Assert.equal(summary.crossingSurfacePartCount, 1, "expected one explicit crossing surface part")
    Assert.equal(summary.curbSurfacePartCount, 1, "expected one explicit curb surface part")
    Assert.equal(
        summary.roadSurfacePartCountByKind.secondary.surfacePartCount,
        2,
        "expected secondary road+curb surfaces"
    )
    Assert.equal(
        summary.roadSurfacePartCountByKind.secondary.featureCount,
        5,
        "expected secondary road+curb feature-equivalent count"
    )
    Assert.equal(
        summary.roadSurfacePartCountByKind.secondary.sourceIds[1],
        "road_1",
        "expected first secondary source id"
    )
    Assert.equal(
        summary.roadSurfacePartCountByKind.secondary.sourceIds[5],
        "road_8",
        "expected last secondary source id"
    )
    Assert.equal(
        summary.roadSurfacePartCountByKind.footway.surfacePartCount,
        2,
        "expected footway sidewalk+crossing surfaces"
    )
    Assert.equal(
        summary.roadSurfacePartCountByKind.footway.featureCount,
        3,
        "expected footway sidewalk+crossing feature-equivalent count"
    )
    Assert.equal(summary.roadSurfacePartCountByKind.footway.sourceIds[3], "road_6", "expected footway source ids")
    Assert.equal(
        summary.roadSurfacePartCountBySubkind.sidewalk.surfacePartCount,
        1,
        "expected one sidewalk subkind surface"
    )
    Assert.equal(
        summary.roadSurfacePartCountBySubkind.sidewalk.featureCount,
        2,
        "expected sidewalk subkind feature-equivalent count"
    )
    Assert.equal(summary.roadSurfacePartCountBySubkind.sidewalk.sourceIds[2], "road_5", "expected sidewalk source ids")
    Assert.equal(
        summary.roadSurfacePartCountBySubkind.crossing.surfacePartCount,
        1,
        "expected one crossing subkind surface"
    )
    Assert.equal(
        summary.roadSurfacePartCountBySubkind.crossing.featureCount,
        1,
        "expected crossing subkind feature-equivalent count"
    )
    Assert.equal(summary.roadSurfacePartCountBySubkind.curb.surfacePartCount, 1, "expected one curb subkind surface")
    Assert.equal(
        summary.roadSurfacePartCountBySubkind.curb.featureCount,
        2,
        "expected one curb feature-equivalent count"
    )
    Assert.equal(summary.roadSurfacePartCountBySubkind.curb.sourceIds[2], "road_8", "expected curb source ids")
    Assert.equal(summary.roadCrosswalkStripeCount, 1, "expected one crosswalk stripe")
    Assert.equal(summary.roadDetailPartCount, 1, "expected one road detail part")
    Assert.equal(summary.chunksWithSidewalkSurfaces, 1, "expected one chunk with sidewalk surfaces")
    Assert.equal(summary.chunksWithCrossingSurfaces, 1, "expected one chunk with crossing surfaces")
    Assert.equal(summary.chunksWithCurbSurfaces, 1, "expected one chunk with curb surfaces")
    Assert.equal(summary.railReceiptCount, 2, "expected two rail audit receipts")
    Assert.equal(summary.chunksWithRailGeometry, 1, "expected one chunk with rail receipts")
    Assert.equal(summary.railReceiptCountByKind.rail.instanceCount, 1, "expected one rail receipt")
    Assert.equal(summary.railReceiptCountByKind.rail.sourceIds[1], "osm_rail_1", "expected rail source id")
    Assert.equal(summary.railReceiptCountByKind.tram.instanceCount, 1, "expected one tram receipt")
    Assert.equal(summary.propInstanceCount, 4, "expected four authored prop roots in the scene")
    Assert.equal(summary.propInstanceCountByKind.tree.instanceCount, 3, "expected three tree props")
    Assert.equal(summary.propInstanceCountByKind.tree.sourceIds[1], "tree_oak_1", "expected tree prop source id")
    Assert.equal(summary.propInstanceCountByKind.tree.sourceIds[3], "tree_cedar_1", "expected tree prop source ids")
    Assert.equal(summary.propInstanceCountByKind.fountain.instanceCount, 1, "expected one fountain prop")
    Assert.equal(summary.propInstanceCountByKind.fountain.sourceIds[1], "fountain_1", "expected fountain source id")
    Assert.equal(summary.treeInstanceCount, 3, "expected three tree instances")
    Assert.equal(summary.treeInstanceCountBySpecies.oak.instanceCount, 1, "expected one oak tree instance")
    Assert.equal(summary.treeInstanceCountBySpecies.oak.sourceIds[1], "tree_oak_1", "expected oak source id")
    Assert.equal(summary.treeInstanceCountBySpecies.elm.instanceCount, 1, "expected one elm tree instance")
    Assert.equal(summary.treeInstanceCountBySpecies.cedar.instanceCount, 1, "expected one cedar tree instance")
    Assert.equal(summary.vegetationInstanceCount, 3, "expected three vegetation instances")
    Assert.equal(summary.vegetationInstanceCountByKind.tree.instanceCount, 3, "expected tree vegetation count")
    Assert.equal(
        summary.vegetationInstanceCountByKind.tree.sourceIds[2],
        "tree_elm_1",
        "expected vegetation source ids"
    )
    Assert.equal(summary.treeModelsWithConnectedTrunkCanopy, 1, "expected one connected tree")
    Assert.equal(summary.treeModelsMissingTrunk, 1, "expected one canopy-only tree")
    Assert.equal(summary.treeModelsMissingCanopy, 0, "expected no trunk-only trees")
    Assert.equal(summary.treeModelsWithDetachedCanopy, 1, "expected one detached-canopy tree")
    Assert.equal(summary.treeConnectivityBySpecies.oak.missingTrunkCount, 1, "expected oak missing trunk count")
    Assert.equal(summary.treeConnectivityBySpecies.elm.connectedCount, 1, "expected elm connected count")
    Assert.equal(summary.treeConnectivityBySpecies.cedar.detachedCanopyCount, 1, "expected cedar detached count")
    Assert.equal(summary.proceduralTreeInstanceCount, 1, "expected one procedural tree instance")
    Assert.equal(
        summary.proceduralTreeModelsWithConnectedTrunkCanopy,
        1,
        "expected one connected procedural landuse tree"
    )
    Assert.equal(
        summary.proceduralTreeConnectivityByKind.park.connectedCount,
        1,
        "expected procedural park tree connectivity to be tracked"
    )
    Assert.equal(summary.chunksWithProps, 1, "expected one chunk with props")
    Assert.equal(summary.chunksWithVegetation, 1, "expected one chunk with vegetation")
    Assert.equal(summary.ambientPropInstanceCount, 1, "expected one ambient prop instance")
    Assert.equal(
        summary.ambientPropInstanceCountByKind.unknown.instanceCount,
        1,
        "expected ambient unknown prop classification"
    )
    Assert.equal(summary.chunksWithAmbientProps, 1, "expected one chunk with ambient props")

    local waterFolder = Instance.new("Folder")
    waterFolder.Name = "Water"
    waterFolder.Parent = chunkFolder

    local polygonSurface = Instance.new("Part")
    polygonSurface.Name = "PolygonWaterSurface_1"
    polygonSurface:SetAttribute("ArnisWaterSurfaceType", "polygon")
    polygonSurface:SetAttribute("ArnisWaterKind", "pond")
    polygonSurface:SetAttribute("ArnisWaterSourceId", "water_poly_1")
    polygonSurface.Parent = waterFolder

    local ribbonSurface = Instance.new("Part")
    ribbonSurface.Name = "RibbonWaterSurface"
    ribbonSurface:SetAttribute("ArnisWaterSurfaceType", "ribbon")
    ribbonSurface:SetAttribute("ArnisWaterKind", "stream")
    ribbonSurface:SetAttribute("ArnisWaterSourceId", "water_ribbon_1")
    ribbonSurface.Parent = waterFolder

    summary = SceneAudit.summarizeWorld(worldRoot)

    Assert.equal(summary.waterSurfacePartCount, 2, "expected two explicit water surface parts")
    Assert.equal(summary.chunksWithWaterGeometry, 1, "expected one chunk with water geometry")
    Assert.equal(summary.waterSurfacePartCountByType.polygon.surfacePartCount, 1, "expected one polygon water surface")
    Assert.equal(summary.waterSurfacePartCountByType.ribbon.surfacePartCount, 1, "expected one ribbon water surface")
    Assert.equal(summary.waterSurfacePartCountByKind.pond.surfacePartCount, 1, "expected one pond water surface")
    Assert.equal(summary.waterSurfacePartCountByKind.stream.surfacePartCount, 1, "expected one stream water surface")
    Assert.equal(summary.waterSurfacePartCountByKind.pond.sourceIds[1], "water_poly_1", "expected pond source id")
    Assert.equal(summary.waterSurfacePartCountByKind.stream.sourceIds[1], "water_ribbon_1", "expected stream source id")

    worldRoot:Destroy()
end

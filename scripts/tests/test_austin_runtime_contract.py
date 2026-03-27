#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
BOOTSTRAP_PATH = ROOT / "roblox" / "src" / "ServerScriptService" / "BootstrapAustin.server.lua"
RUN_AUSTIN_PATH = ROOT / "roblox" / "src" / "ServerScriptService" / "ImportService" / "RunAustin.lua"
STREAMING_SERVICE_PATH = ROOT / "roblox" / "src" / "ServerScriptService" / "ImportService" / "StreamingService.lua"
IMPORT_SERVICE_PATH = ROOT / "roblox" / "src" / "ServerScriptService" / "ImportService" / "init.lua"
SIGNATURES_PATH = ROOT / "roblox" / "src" / "ServerScriptService" / "ImportService" / "ImportSignatures.lua"
WORLD_PROBE_PATH = ROOT / "roblox" / "src" / "StarterPlayer" / "StarterPlayerScripts" / "WorldProbe.client.lua"


class AustinRuntimeContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.bootstrap_text = BOOTSTRAP_PATH.read_text(encoding="utf-8")
        cls.run_austin_text = RUN_AUSTIN_PATH.read_text(encoding="utf-8")
        cls.streaming_text = STREAMING_SERVICE_PATH.read_text(encoding="utf-8")
        cls.import_service_text = IMPORT_SERVICE_PATH.read_text(encoding="utf-8")
        cls.signatures_text = SIGNATURES_PATH.read_text(encoding="utf-8") if SIGNATURES_PATH.exists() else ""
        cls.world_probe_text = WORLD_PROBE_PATH.read_text(encoding="utf-8") if WORLD_PROBE_PATH.exists() else ""

    def test_bootstrap_guards_against_duplicate_runtime_execution(self) -> None:
        self.assertIn('local BOOTSTRAP_STATE_ATTR = "ArnisAustinBootstrapState"', self.bootstrap_text)
        self.assertIn('local BOOTSTRAP_STATE_TRACE_ATTR = "ArnisAustinBootstrapStateTrace"', self.bootstrap_text)
        self.assertIn('local BOOTSTRAP_DUPLICATE_COUNT_ATTR = "ArnisAustinBootstrapDuplicateCount"', self.bootstrap_text)
        self.assertIn('local BOOTSTRAP_ENTRY_COUNT_ATTR = "ArnisAustinBootstrapEntryCount"', self.bootstrap_text)
        self.assertIn('local BOOTSTRAP_LAST_SCRIPT_PATH_ATTR = "ArnisAustinBootstrapLastScriptPath"', self.bootstrap_text)
        self.assertIn("local function setBootstrapState(state)", self.bootstrap_text)
        self.assertIn('Workspace:SetAttribute(BOOTSTRAP_STATE_TRACE_ATTR, table.concat(trace, ","))', self.bootstrap_text)
        self.assertIn("Workspace:SetAttribute(BOOTSTRAP_ENTRY_COUNT_ATTR, entryCount)", self.bootstrap_text)
        self.assertIn('Workspace:SetAttribute(BOOTSTRAP_LAST_SCRIPT_PATH_ATTR, script:GetFullName())', self.bootstrap_text)
        self.assertIn('local existingBootstrapState = Workspace:GetAttribute(BOOTSTRAP_STATE_ATTR)', self.bootstrap_text)
        self.assertIn('if existingBootstrapState == "failed" then', self.bootstrap_text)
        self.assertIn('Workspace:SetAttribute(BOOTSTRAP_STATE_ATTR, nil)', self.bootstrap_text)
        self.assertIn('Workspace:SetAttribute(BOOTSTRAP_STATE_TRACE_ATTR, nil)', self.bootstrap_text)
        self.assertIn('reportPhase(options, "loading_manifest")', self.run_austin_text)
        self.assertIn('reportPhase(options, "importing_startup")', self.run_austin_text)
        self.assertIn('setBootstrapState("world_ready")', self.bootstrap_text)
        self.assertIn('setBootstrapState("streaming_ready")', self.bootstrap_text)
        self.assertIn('setBootstrapState("minimap_ready")', self.bootstrap_text)
        self.assertIn('setBootstrapState("gameplay_ready")', self.bootstrap_text)
        self.assertIn('setBootstrapState("failed")', self.bootstrap_text)
        self.assertIn('Workspace:SetAttribute(BOOTSTRAP_DUPLICATE_COUNT_ATTR, duplicateCount)', self.bootstrap_text)
        self.assertIn('"[BootstrapAustin] Duplicate bootstrap attempt ignored. state="', self.bootstrap_text)

    def test_bootstrap_lifts_characters_above_spawn_surface_before_pivoting(self) -> None:
        self.assertIn("local function getCharacterSpawnCFrame(character)", self.bootstrap_text)
        self.assertIn("local extents = character:GetExtentsSize()", self.bootstrap_text)
        self.assertIn("local spawnLift = math.max(6, extents.Y * 0.5 + 0.5)", self.bootstrap_text)
        self.assertIn("local elevatedPosition = basePosition + Vector3.new(0, spawnLift, 0)", self.bootstrap_text)
        self.assertIn("local characterSpawnCFrame = getCharacterSpawnCFrame(character)", self.bootstrap_text)
        self.assertIn("character:PivotTo(characterSpawnCFrame)", self.bootstrap_text)

    def test_bootstrap_hides_respawn_pad_and_uses_ground_surface_not_double_lift(self) -> None:
        self.assertIn("local function isDecorativeRoadDetailDescendant(hitInstance, worldRoot)", self.bootstrap_text)
        self.assertIn('if isDecorativeRoadDetailDescendant(hitInstance, worldRoot) then', self.bootstrap_text)
        self.assertIn("return hit.Position.Y", self.bootstrap_text)
        self.assertIn("spawn.Transparency = 1", self.bootstrap_text)
        self.assertIn("spawn.CanCollide = false", self.bootstrap_text)
        self.assertIn("local spawnSurfaceY = findGroundYNear(worldRoot, spawnPoint, holdingPad, spawn)", self.bootstrap_text)
        self.assertIn("local spawnCenterY = spawnSurfaceY + spawn.Size.Y * 0.5", self.bootstrap_text)
        self.assertIn("local lookTarget = Vector3.new(preferredLookTarget.X, spawnSurfaceY, preferredLookTarget.Z)", self.bootstrap_text)
        self.assertIn("spawn.CFrame = CFrame.new(spawnPoint.X, spawnCenterY, spawnPoint.Z)", self.bootstrap_text)
        self.assertIn("spawnCFrame = CFrame.lookAt(Vector3.new(spawnPoint.X, spawnSurfaceY, spawnPoint.Z), lookTarget)", self.bootstrap_text)

    def test_run_austin_publishes_runtime_world_root_telemetry(self) -> None:
        self.assertIn('setPerfAttribute("WorldRootName", "GeneratedWorld_Austin")', self.run_austin_text)
        self.assertIn('setPerfAttribute("WorldRootChildCount", #worldRoot:GetChildren())', self.run_austin_text)
        self.assertIn('setPerfAttribute("WorldRootDescendantCount", #worldRoot:GetDescendants())', self.run_austin_text)
        self.assertIn('setPerfAttribute("WorldRootExists", 1)', self.run_austin_text)
        self.assertIn('setPerfAttribute("WorldRootExists", 0)', self.run_austin_text)

    def test_streaming_service_publishes_startup_residency_telemetry(self) -> None:
        self.assertIn('Workspace:SetAttribute("ArnisStreamingLoadedChunkCount", 0)', self.streaming_text)
        self.assertIn('Workspace:SetAttribute("ArnisStreamingDesiredChunkCount", 0)', self.streaming_text)
        self.assertIn('Workspace:SetAttribute("ArnisStreamingCandidateChunkCount", 0)', self.streaming_text)
        self.assertIn('Workspace:SetAttribute("ArnisStreamingProcessedWorkItems", 0)', self.streaming_text)
        self.assertIn('Workspace:SetAttribute("ArnisStreamingLastFocalX", 0)', self.streaming_text)
        self.assertIn('Workspace:SetAttribute("ArnisStreamingLastFocalZ", 0)', self.streaming_text)
        self.assertIn('Workspace:SetAttribute("ArnisStreamingLoadedChunkCount"', self.streaming_text)
        self.assertIn('#ChunkLoader.ListLoadedChunks(streamingOptions.worldRootName)', self.streaming_text)
        self.assertIn('Workspace:SetAttribute("ArnisStreamingCandidateChunkCount", #candidateChunkEntries)', self.streaming_text)
        self.assertIn('Workspace:SetAttribute("ArnisStreamingDesiredChunkCount", desiredChunkCount)', self.streaming_text)
        self.assertIn('Workspace:SetAttribute("ArnisStreamingProcessedWorkItems", processedWorkItems)', self.streaming_text)

    def test_startup_import_and_streaming_share_chunk_signature_contract(self) -> None:
        self.assertIn("local ImportSignatures = require(script.Parent.ImportSignatures)", self.streaming_text)
        self.assertIn("local ImportSignatures = require(script.ImportSignatures)", self.import_service_text)
        self.assertIn("ImportSignatures.GetChunkSignature(chunkRef)", self.streaming_text)
        self.assertIn("perChunkOptions.chunkSignature = ImportSignatures.GetChunkSignature(", self.import_service_text)
        self.assertIn("configSignature = ImportSignatures.GetConfigSignature(config)", self.import_service_text)
        self.assertIn("layerSignatures = ImportSignatures.GetLayerSignatures(config)", self.import_service_text)
        self.assertIn("function ImportSignatures.GetChunkSignature(chunkRef)", self.signatures_text)
        self.assertIn("function ImportSignatures.GetConfigSignature(config)", self.signatures_text)
        self.assertIn("function ImportSignatures.GetLayerSignatures(config)", self.signatures_text)

    def test_runtime_startup_import_registers_canonical_chunk_refs(self) -> None:
        self.assertIn("local startupChunkRefsById = {}", self.run_austin_text)
        self.assertIn("startupChunkRefsById[chunkId] = manifestSource:ResolveChunkRef(chunkId)", self.run_austin_text)
        self.assertIn("registrationChunksById = startupChunkRefsById", self.run_austin_text)
        self.assertIn("local registrationChunksById = options.registrationChunksById", self.import_service_text)
        self.assertIn("local registrationChunk = registrationChunksById and registrationChunksById[chunk.id] or nil", self.import_service_text)
        self.assertIn("perChunkOptions.registrationChunk = registrationChunk", self.import_service_text)
        self.assertIn("perChunkOptions.chunkSignature = ImportSignatures.GetChunkSignature(registrationChunk or chunk)", self.import_service_text)

    def test_client_world_probe_publishes_nearby_building_and_overhead_roof_telemetry(self) -> None:
        self.assertIn('print("ARNIS_CLIENT_WORLD " .. HttpService:JSONEncode(', self.world_probe_text)
        self.assertIn('local worldRootName = Workspace:GetAttribute("ArnisMinimapWorldRootName")', self.world_probe_text)
        self.assertIn('local worldRoot = Workspace:FindFirstChild(worldRootName)', self.world_probe_text)
        self.assertIn("local function isDecorativeRoadDetailDescendant(hitInstance)", self.world_probe_text)
        self.assertIn("if isDecorativeRoadDetailDescendant(rayResult.Instance) then", self.world_probe_text)
        self.assertIn('model:GetAttribute("ArnisImportSourceId")', self.world_probe_text)
        self.assertIn('model:GetAttribute("ArnisImportRoofShape")', self.world_probe_text)
        self.assertIn('model:GetAttribute("ArnisImportBuildingTopY")', self.world_probe_text)
        self.assertIn('local mergedMeshes = buildingsFolder:FindFirstChild("MergedMeshes")', self.world_probe_text)
        self.assertIn("nearbyMergedBuildingMeshParts", self.world_probe_text)
        self.assertIn("local rayResult = Workspace:Raycast(", self.world_probe_text)
        self.assertIn("groundMaterial =", self.world_probe_text)
        self.assertIn('overheadRoofParts', self.world_probe_text)
        self.assertIn('nearbyBuildingModels', self.world_probe_text)

    def test_runtime_contract_exposes_bootstrap_state_trace_for_ordered_readiness_assertions(self) -> None:
        self.assertIn('local BOOTSTRAP_STATE_TRACE_ATTR = "ArnisAustinBootstrapStateTrace"', self.bootstrap_text)
        self.assertIn('reportPhase(options, "loading_manifest")', self.run_austin_text)
        self.assertIn('reportPhase(options, "importing_startup")', self.run_austin_text)
        self.assertIn('setBootstrapState("world_ready")', self.bootstrap_text)
        self.assertIn('setBootstrapState("streaming_ready")', self.bootstrap_text)
        self.assertIn('if runtimeWorldConfig.EnableMinimap ~= false and Workspace:GetAttribute("ArnisMinimapEnabled") ~= true then', self.bootstrap_text)
        self.assertIn('setBootstrapState("minimap_ready")', self.bootstrap_text)
        self.assertIn('setBootstrapState("gameplay_ready")', self.bootstrap_text)


if __name__ == "__main__":
    unittest.main()

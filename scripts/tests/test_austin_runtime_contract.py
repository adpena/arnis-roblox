#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
BOOTSTRAP_PATH = ROOT / "roblox" / "src" / "ServerScriptService" / "BootstrapAustin.server.lua"
BOOTSTRAP_STATE_MACHINE_PATH = ROOT / "roblox" / "src" / "ServerScriptService" / "ImportService" / "BootstrapStateMachine.lua"
RUN_AUSTIN_PATH = ROOT / "roblox" / "src" / "ServerScriptService" / "ImportService" / "RunAustin.lua"
HARNESS_PATH = ROOT / "scripts" / "run_studio_harness.sh"
BUILDING_BUILDER_PATH = (
    ROOT / "roblox" / "src" / "ServerScriptService" / "ImportService" / "Builders" / "BuildingBuilder.lua"
)
ROOF_TRUTH_PATH = ROOT / "roblox" / "src" / "ServerScriptService" / "Tests" / "RoofTruth.spec.lua"
ROOF_ONLY_ATTACHMENT_PATH = (
    ROOT / "roblox" / "src" / "ServerScriptService" / "Tests" / "RoofOnlyRooftopAttachment.spec.lua"
)
TERRAIN_ALIGNMENT_PATH = ROOT / "roblox" / "src" / "ServerScriptService" / "Tests" / "TerrainAlignment.spec.lua"
RUST_PIPELINE_PATH = ROOT / "rust" / "crates" / "arbx_pipeline" / "src" / "lib.rs"


class AustinRuntimeContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.bootstrap_text = BOOTSTRAP_PATH.read_text(encoding="utf-8")
        cls.machine_text = BOOTSTRAP_STATE_MACHINE_PATH.read_text(encoding="utf-8")
        cls.run_austin_text = RUN_AUSTIN_PATH.read_text(encoding="utf-8")
        cls.harness_text = HARNESS_PATH.read_text(encoding="utf-8")
        cls.building_builder_text = BUILDING_BUILDER_PATH.read_text(encoding="utf-8")
        cls.roof_truth_text = ROOF_TRUTH_PATH.read_text(encoding="utf-8")
        cls.roof_only_attachment_text = (
            ROOF_ONLY_ATTACHMENT_PATH.read_text(encoding="utf-8")
            if ROOF_ONLY_ATTACHMENT_PATH.exists()
            else ""
        )
        cls.terrain_alignment_text = TERRAIN_ALIGNMENT_PATH.read_text(encoding="utf-8")
        cls.rust_pipeline_text = RUST_PIPELINE_PATH.read_text(encoding="utf-8")

    def test_bootstrap_uses_shared_state_machine_with_attempt_identity(self) -> None:
        self.assertIn("local BootstrapStateMachine = require(script.Parent.ImportService.BootstrapStateMachine)", self.bootstrap_text)
        self.assertIn('local BOOTSTRAP_ATTEMPT_ID_ATTR = BootstrapStateMachine.ATTEMPT_ID_ATTR', self.bootstrap_text)
        self.assertIn("local bootstrapMachine, duplicateInfo = BootstrapStateMachine.begin(Workspace, script:GetFullName())", self.bootstrap_text)
        self.assertIn('"[BootstrapAustin] Duplicate bootstrap attempt ignored. state="', self.bootstrap_text)
        self.assertIn('BootstrapStateMachine.fail(bootstrapMachine)', self.bootstrap_text)
        self.assertIn('setBootstrapState("world_ready")', self.bootstrap_text)
        self.assertIn('setBootstrapState("streaming_ready")', self.bootstrap_text)
        self.assertIn('setBootstrapState("minimap_ready")', self.bootstrap_text)
        self.assertIn('setBootstrapState("gameplay_ready")', self.bootstrap_text)
        self.assertIn('phaseReporter = setBootstrapState', self.bootstrap_text)
        self.assertIn('reportPhase(options, "loading_manifest")', self.run_austin_text)
        self.assertIn('reportPhase(options, "importing_startup")', self.run_austin_text)

    def test_bootstrap_state_machine_rejects_duplicate_and_regressive_transitions(self) -> None:
        self.assertIn('BootstrapStateMachine.STATE_ATTR = "ArnisAustinBootstrapState"', self.machine_text)
        self.assertIn('BootstrapStateMachine.ATTEMPT_ID_ATTR = "ArnisAustinBootstrapAttemptId"', self.machine_text)
        self.assertIn('BootstrapStateMachine.ATTEMPT_SEQUENCE_ATTR = "ArnisAustinBootstrapAttemptSequence"', self.machine_text)
        self.assertIn('workspace:SetAttribute(BootstrapStateMachine.STATE_ATTR, nil)', self.machine_text)
        self.assertIn('workspace:SetAttribute(BootstrapStateMachine.STATE_TRACE_ATTR, nil)', self.machine_text)
        self.assertIn('workspace:SetAttribute(BootstrapStateMachine.ATTEMPT_ID_ATTR, nil)', self.machine_text)
        self.assertIn('local attemptId = "attempt-" .. tostring(attemptSequence)', self.machine_text)
        self.assertIn('error("duplicate bootstrap state transition: " .. tostring(nextState))', self.machine_text)
        self.assertIn('error("bootstrap state machine is already terminal")', self.machine_text)
        self.assertIn('error(', self.machine_text)
        self.assertIn('"bootstrap state regression from %s to %s"', self.machine_text)

    def test_play_probe_captures_bootstrap_identity_and_trace(self) -> None:
        self.assertIn('payload.bootstrapState = Workspace:GetAttribute("ArnisAustinBootstrapState")', self.harness_text)
        self.assertIn('payload.bootstrapAttemptId = Workspace:GetAttribute("ArnisAustinBootstrapAttemptId")', self.harness_text)
        self.assertIn('payload.bootstrapStateTrace = Workspace:GetAttribute("ArnisAustinBootstrapStateTrace")', self.harness_text)
        self.assertIn('payload.bootstrapDuplicateCount = Workspace:GetAttribute("ArnisAustinBootstrapDuplicateCount")', self.harness_text)

    def test_task_five_canonicalizes_play_presentation_truth(self) -> None:
        self.assertIn('BuildingMode = "shellMesh"', self.roof_truth_text)
        self.assertNotIn('BuildingMode = "shellParts"', self.roof_truth_text)
        self.assertIn('TerrainMode = "paint"', self.terrain_alignment_text)
        self.assertIn('RoadMode = "parts"', self.terrain_alignment_text)
        self.assertIn("ArnisImportRoofOnlyAttachment", self.building_builder_text)
        self.assertIn("let visible_height = (height - base_y).max(0.0);", self.rust_pipeline_text)
        self.assertTrue(
            ROOF_ONLY_ATTACHMENT_PATH.exists(),
            "expected dedicated roof-only rooftop attachment spec to exist",
        )
        self.assertIn("ArnisImportRoofOnlyAttachment", self.roof_only_attachment_text)
        self.assertIn("SupportPost", self.roof_only_attachment_text)


if __name__ == "__main__":
    unittest.main()

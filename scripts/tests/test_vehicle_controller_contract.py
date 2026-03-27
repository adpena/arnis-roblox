#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
VEHICLE_CONTROLLER_PATH = (
    ROOT / "roblox" / "src" / "StarterPlayer" / "StarterPlayerScripts" / "VehicleController.client.lua"
)


class VehicleControllerContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.text = VEHICLE_CONTROLLER_PATH.read_text(encoding="utf-8")

    def test_vehicle_controller_resolves_current_camera_dynamically(self) -> None:
        self.assertNotIn("local camera = workspace.CurrentCamera", self.text)
        self.assertIn("local function getCamera()", self.text)
        self.assertIn("return Workspace.CurrentCamera", self.text)

    def test_vehicle_controller_restores_default_camera_subject_after_spawn(self) -> None:
        self.assertIn("local function restoreDefaultCamera(humanoid)", self.text)
        self.assertIn("camera.CameraType = Enum.CameraType.Custom", self.text)
        self.assertIn("camera.CameraSubject = humanoid", self.text)
        self.assertIn("restoreDefaultCamera(hum)", self.text)

    def test_vehicle_controller_publishes_client_camera_telemetry(self) -> None:
        self.assertIn('player:SetAttribute("ArnisVehicleControllerReady", true)', self.text)
        self.assertIn("local function publishClientCameraTelemetry(humanoid)", self.text)
        self.assertIn('ArnisClientCameraType = camera and tostring(camera.CameraType) or nil', self.text)
        self.assertIn('ArnisClientCameraSubject = subject and subject:GetFullName() or nil', self.text)
        self.assertIn('ArnisClientCameraMode = mode', self.text)
        self.assertIn('ArnisClientCameraSubjectClass = subject and subject.ClassName or nil', self.text)
        self.assertIn("setPlayerAttributeIfChanged(attributeName, nextValue)", self.text)
        self.assertIn('print("ARNIS_CLIENT_CAMERA " .. HttpService:JSONEncode({', self.text)


if __name__ == "__main__":
    unittest.main()

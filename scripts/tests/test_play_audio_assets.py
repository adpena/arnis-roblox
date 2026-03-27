import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
VEHICLE_CONTROLLER = (
    REPO_ROOT / "roblox/src/StarterPlayer/StarterPlayerScripts/VehicleController.client.lua"
)
AMBIENT_SOUNDSCAPE = (
    REPO_ROOT / "roblox/src/StarterPlayer/StarterPlayerScripts/AmbientSoundscape.client.lua"
)
FORBIDDEN_SOUND_IDS = {
    "rbxassetid://9113586364",
    "rbxassetid://9113088613",
    "rbxassetid://9113543029",
    "rbxassetid://9112858785",
    "rbxassetid://9114105209",
    "rbxassetid://9114119441",
    "rbxassetid://9112798601",
}


class PlayAudioAssetsTest(unittest.TestCase):
    def assert_forbidden_ids_absent(self, path: Path) -> None:
        content = path.read_text()
        for sound_id in FORBIDDEN_SOUND_IDS:
            self.assertNotIn(sound_id, content, f"expected {path.name} to stop using {sound_id}")

    def test_vehicle_controller_avoids_known_forbidden_sound_ids(self) -> None:
        self.assert_forbidden_ids_absent(VEHICLE_CONTROLLER)

    def test_ambient_soundscape_avoids_known_forbidden_sound_ids(self) -> None:
        self.assert_forbidden_ids_absent(AMBIENT_SOUNDSCAPE)

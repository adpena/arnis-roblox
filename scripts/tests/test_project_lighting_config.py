from __future__ import annotations

import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
PROJECT_PATH = ROOT / "roblox" / "default.project.json"


class ProjectLightingConfigTests(unittest.TestCase):
    def test_default_project_declares_future_lighting(self) -> None:
        data = json.loads(PROJECT_PATH.read_text())
        lighting = data.get("tree", {}).get("Lighting")
        self.assertIsInstance(lighting, dict)
        self.assertEqual(lighting.get("$className"), "Lighting")
        properties = lighting.get("$properties")
        self.assertIsInstance(properties, dict)
        self.assertEqual(properties.get("Technology"), "Future")

    def test_default_project_publishes_generic_vertigo_sync_server_url(self) -> None:
        data = json.loads(PROJECT_PATH.read_text())
        serve_port = data.get("servePort")
        self.assertIsInstance(serve_port, int)

        workspace = data.get("tree", {}).get("Workspace")
        self.assertIsInstance(workspace, dict)
        attributes = workspace.get("$attributes")
        self.assertIsInstance(attributes, dict)
        self.assertEqual(
            attributes.get("VertigoSyncServerUrl"),
            f"http://127.0.0.1:{serve_port}",
        )


if __name__ == "__main__":
    unittest.main()

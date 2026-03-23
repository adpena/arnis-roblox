from __future__ import annotations

import json
import shutil
import subprocess
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ROBLOX_ROOT = ROOT / "roblox"
VERTIGO_SYNC_ROOT = ROOT.parent / "vertigo-sync"

TARGET_RULES_BY_PATH = {
    "src/ServerScriptService/BootstrapAustin.server.lua": {"perf-unfrozen-constant"},
    "src/ServerScriptService/ImportService/RoadProfile.lua": {
        "ncg-untyped-param",
        "perf-unfrozen-constant",
    },
    "src/ServerScriptService/ImportService/GroundSampler.lua": {"ncg-untyped-param"},
    "src/ServerScriptService/ImportService/SpatialQuery.lua": {"ncg-untyped-param"},
    "src/ServerScriptService/ImportService/ManifestLoader.lua": {"perf-dynamic-array"},
    "src/ServerScriptService/StudioPreview/AustinPreviewBuilder.lua": {"perf-dynamic-array"},
    "src/ServerScriptService/ImportService/Builders/WaterBuilder.lua": {"perf-dynamic-array"},
    "src/ServerScriptService/ImportService/AustinSpawn.lua": {"perf-unfrozen-constant"},
    "src/ServerScriptService/ImportService/AmbientLife.lua": {"perf-unfrozen-constant"},
    "src/ServerScriptService/ImportService/DayNightCycle.lua": {"perf-unfrozen-constant"},
    "src/ServerScriptService/ImportService/ImportPlanCache.lua": {"perf-unfrozen-constant"},
    "src/ServerScriptService/ImportService/MinimapService.lua": {"perf-unfrozen-constant"},
}


def run_vsync_validate() -> dict[str, object]:
    cargo = shutil.which("cargo")
    if cargo is None:
        raise unittest.SkipTest("cargo is required to run vsync validate")
    if not VERTIGO_SYNC_ROOT.exists():
        raise unittest.SkipTest("adjacent vertigo-sync repo is required for this test")

    result = subprocess.run(
        [
            cargo,
            "run",
            "--manifest-path",
            str(VERTIGO_SYNC_ROOT / "Cargo.toml"),
            "--",
            "--root",
            str(ROBLOX_ROOT),
            "validate",
            "--json",
        ],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=True,
    )

    return json.loads(result.stdout)


class VsyncValidateHotPathsTest(unittest.TestCase):
    maxDiff = None

    def test_hot_path_warnings_are_clean(self) -> None:
        summary = run_vsync_validate()
        issues = summary["source"]["issues"]
        offenders: list[str] = []

        for issue in issues:
            path = issue["path"]
            rule = issue["rule"]
            if rule in TARGET_RULES_BY_PATH.get(path, set()):
                offenders.append(f"{path}:{issue['line']} {rule} {issue['message']}")

        self.assertEqual([], offenders)


if __name__ == "__main__":
    unittest.main()

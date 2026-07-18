import json
from pathlib import Path
import tempfile
import unittest

from backend.painting_world import PaintingPromptResolver
from backend.server import prompt_for


STATE = {"brightness": .5, "warmth": .5, "abstraction": .5, "motion": .5, "tension": .5}


def profile(identifier, artist, filename, default):
    return {
        "id": identifier,
        "title": identifier.replace("-", " ").title(),
        "artist": artist,
        "resourceFilename": filename,
        "defaultState": {key: default for key in STATE},
        "visualBias": {
            "palette": f"{identifier} palette",
            "brush": f"{identifier} brush",
            "structure": f"{identifier} structure",
        },
        "promptBias": [f"{identifier} subject"],
    }


class PaintingPromptResolverTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.directory = Path(self.temporary.name)
        self.catalog = {
            "version": 1,
            "defaultPaintingID": "calm-world",
            "rotation": {"stateBias": .12},
            "paintings": [
                profile("calm-world", "Artist A", "calm.png", .2),
                profile("active-world", "Artist B", "active.png", .8),
            ],
        }
        (self.directory / "catalog.json").write_text(json.dumps(self.catalog))

    def tearDown(self):
        self.temporary.cleanup()

    def test_resource_path_resolves_profile_and_bounded_state_bias(self):
        resolver = PaintingPromptResolver()
        influence = resolver.resolve(str(self.directory / "calm.png"))
        self.assertIsNotNone(influence)
        self.assertEqual(influence.current.id, "calm-world")
        adjusted = influence.adjusted_state(STATE)
        self.assertTrue(all(0 <= value <= 1 for value in adjusted.values()))
        self.assertAlmostEqual(adjusted["motion"], .464)
        self.assertIn("Artist A", prompt_for(adjusted, influence))
        self.assertIn("calm-world subject", prompt_for(adjusted, influence))
        self.assertLessEqual(len(prompt_for(adjusted, influence).split()), 65)

    def test_bridge_filename_resolves_both_profiles_deterministically(self):
        resolver = PaintingPromptResolver()
        resolver.resolve(str(self.directory / "calm.png"))
        first = resolver.resolve("/tmp/world-anchor__0__1__500.png")
        second = resolver.resolve("/tmp/world-anchor__0__1__500.png")
        self.assertEqual(first, second)
        self.assertEqual(first.current.id, "calm-world")
        self.assertEqual(first.target.id, "active-world")
        self.assertEqual(first.progress, .5)
        self.assertAlmostEqual(first.adjusted_state(STATE)["motion"], .5)
        prompt = prompt_for(STATE, first)
        self.assertIn("continuous painted bridge", prompt)
        self.assertIn("target 0.50", prompt)
        self.assertLessEqual(len(prompt.split()), 65)

    def test_bridge_resolves_after_service_restart_from_sibling_catalog(self):
        influence = PaintingPromptResolver().resolve(
            str(self.directory / "world-anchor__0__1__500.png")
        )
        self.assertIsNotNone(influence)
        self.assertEqual((influence.current.id, influence.target.id), ("calm-world", "active-world"))

    def test_unknown_or_malformed_anchor_keeps_base_behavior(self):
        resolver = PaintingPromptResolver()
        self.assertIsNone(resolver.resolve("/tmp/unrelated.png"))
        resolver.resolve(str(self.directory / "calm.png"))
        self.assertIsNone(resolver.resolve("/tmp/world-anchor__0__99__500.png"))
        self.assertIsNone(resolver.resolve("/tmp/world-anchor__0__1__jitter.png"))

    def test_profile_bias_never_exceeds_twenty_percent(self):
        self.catalog["rotation"]["stateBias"] = 1
        (self.directory / "catalog.json").write_text(json.dumps(self.catalog))
        influence = PaintingPromptResolver().resolve(str(self.directory / "active.png"))
        adjusted = influence.adjusted_state({key: 0 for key in STATE})
        for value in adjusted.values():
            self.assertAlmostEqual(value, .16)


if __name__ == "__main__":
    unittest.main()

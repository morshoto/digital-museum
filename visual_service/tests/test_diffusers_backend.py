import io
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from visual_service.server import DiffusersBackend, artistic_state, diffusion_settings, model_load_source, prompt_for


VALID_STATE = {"brightness": .5, "warmth": .5, "abstraction": .3, "motion": .4, "tension": .2}


class DiffusionMappingTests(unittest.TestCase):
    def test_artistic_state_is_bounded_and_deterministic(self):
        for state in (
            {key: 0 for key in VALID_STATE},
            VALID_STATE,
            {key: 1 for key in VALID_STATE},
        ):
            first = artistic_state(state)
            self.assertEqual(first, artistic_state(state))
            for value in first.__dict__.values():
                self.assertGreaterEqual(value, 0)
                self.assertLessEqual(value, 1)

    def test_raw_parameters_change_expected_artistic_dimensions(self):
        baseline = artistic_state(VALID_STATE)
        bright = artistic_state(dict(VALID_STATE, brightness=1))
        moving = artistic_state(dict(VALID_STATE, motion=1))
        tense = artistic_state(dict(VALID_STATE, tension=1))
        abstract = artistic_state(dict(VALID_STATE, abstraction=1))
        self.assertGreater(bright.luminosity, baseline.luminosity)
        self.assertGreater(moving.fluidity, baseline.fluidity)
        self.assertGreater(moving.density, baseline.density)
        self.assertGreater(tense.instability, baseline.instability)
        self.assertLess(tense.serenity, baseline.serenity)
        self.assertGreater(abstract.fluidity, baseline.fluidity)
        self.assertGreater(abstract.instability, baseline.instability)

    def test_visual_prompt_consumes_shared_artistic_qualities(self):
        calm = prompt_for({"brightness": .1, "warmth": .1, "abstraction": .1, "motion": .1, "tension": .1})
        turbulent = prompt_for({"brightness": .9, "warmth": .9, "abstraction": .9, "motion": .9, "tension": .9})
        self.assertIn("subdued moonlit", calm)
        self.assertIn("quiet delicate", calm)
        self.assertIn("strongly preserve", calm)
        self.assertIn("radiant luminous", turbulent)
        self.assertIn("turbulent flowing", turbulent)
        self.assertIn("structurally unsettled", turbulent)

    def test_abstraction_and_motion_raise_img2img_strength(self):
        calm = diffusion_settings(dict(VALID_STATE, abstraction=.1, motion=.1), 0, turbo=True)
        active = diffusion_settings(dict(VALID_STATE, abstraction=.9, motion=.9), 0, turbo=True)
        self.assertGreater(active.strength, calm.strength)
        self.assertGreaterEqual(calm.num_inference_steps * calm.strength, 1)

    def test_abstraction_caps_divergence_despite_high_motion_and_tension(self):
        constrained = diffusion_settings(
            dict(VALID_STATE, abstraction=0, motion=1, tension=1),
            0,
            turbo=True,
        )
        self.assertLessEqual(constrained.strength, .30)
        self.assertGreaterEqual(constrained.original_weight, .55)

    def test_artistic_qualities_shape_change_inside_abstraction_allowance(self):
        quiet = diffusion_settings(
            dict(VALID_STATE, abstraction=.6, motion=0, tension=0),
            0,
            turbo=True,
        )
        active = diffusion_settings(
            dict(VALID_STATE, abstraction=.6, motion=1, tension=1),
            0,
            turbo=True,
        )
        abstraction_cap = .30 + .6 * .48
        self.assertGreater(active.strength, quiet.strength)
        self.assertLessEqual(active.strength, abstraction_cap)
        self.assertLessEqual(quiet.strength, abstraction_cap)

    def test_turbo_uses_no_classifier_free_guidance(self):
        low = diffusion_settings(dict(VALID_STATE, tension=0), 0, turbo=True)
        high = diffusion_settings(dict(VALID_STATE, tension=1), 0, turbo=True)
        self.assertEqual(low.guidance_scale, 0)
        self.assertEqual(high.guidance_scale, 0)

    def test_original_anchor_never_falls_below_thirty_percent(self):
        settings = diffusion_settings(dict(VALID_STATE, abstraction=1), 0, turbo=True)
        self.assertGreaterEqual(settings.original_weight, .30)

    def test_instability_raises_non_turbo_guidance_without_breaking_anchor_constraint(self):
        calm = diffusion_settings(dict(VALID_STATE, abstraction=0, motion=0, tension=0), 0, turbo=False)
        unstable = diffusion_settings(dict(VALID_STATE, abstraction=1, motion=1, tension=1), 0, turbo=False)
        self.assertGreater(unstable.guidance_scale, calm.guidance_scale)
        self.assertLess(unstable.original_weight, calm.original_weight)

    def test_motion_and_sequence_change_seed(self):
        first = diffusion_settings(VALID_STATE, 0, turbo=True)
        second = diffusion_settings(VALID_STATE, 1, turbo=True)
        changed_motion = diffusion_settings(dict(VALID_STATE, motion=.9), 0, turbo=True)
        self.assertNotEqual(first.seed, second.seed)
        self.assertNotEqual(first.seed, changed_motion.seed)

    def test_offline_hub_id_resolves_to_downloaded_snapshot(self):
        with tempfile.TemporaryDirectory() as directory:
            repository = Path(directory) / "models--example--model"
            snapshot = repository / "snapshots" / "abc123"
            snapshot.mkdir(parents=True)
            (snapshot / "model_index.json").write_text("{}")
            (repository / "refs").mkdir()
            (repository / "refs" / "main").write_text("abc123\n")
            with patch.dict(os.environ, {"HF_HUB_OFFLINE": "1", "HF_HUB_CACHE": directory}):
                self.assertEqual(model_load_source("example/model"), str(snapshot))

    def test_existing_tilde_model_path_returns_expanded_path(self):
        with tempfile.TemporaryDirectory() as directory:
            model = Path(directory) / "models" / "local-model"
            model.mkdir(parents=True)
            with patch.dict(os.environ, {"HOME": directory}):
                self.assertEqual(model_load_source("~/models/local-model"), str(model))


try:
    from PIL import Image
except ImportError:
    Image = None


@unittest.skipIf(Image is None, "Pillow is only required by the real backend")
class DiffusersBackendTests(unittest.TestCase):
    class FakePipeline:
        def __init__(self):
            self.calls = []

        def __call__(self, **options):
            self.calls.append(options)
            output = options["image"].transpose(Image.Transpose.FLIP_LEFT_RIGHT)
            return type("PipelineResult", (), {"images": [output]})()

    @staticmethod
    def encoded(color, size=(80, 64)):
        buffer = io.BytesIO()
        Image.new("RGB", size, color).save(buffer, format="PNG")
        return buffer.getvalue()

    def test_real_backend_contract_returns_decodable_png(self):
        pipeline = self.FakePipeline()
        backend = DiffusersBackend(width=64, height=64, pipeline=pipeline)
        result = backend.generate(VALID_STATE, self.encoded("red"), self.encoded("blue"))
        self.assertEqual(result.media_type, "image/png")
        image = Image.open(io.BytesIO(result.image))
        self.assertEqual(image.size, (64, 64))
        self.assertEqual(pipeline.calls[0]["num_inference_steps"], 4)
        self.assertEqual(pipeline.calls[0]["guidance_scale"], 0)

    def test_previous_and_original_both_influence_iterative_source(self):
        pipeline = self.FakePipeline()
        backend = DiffusersBackend(width=64, height=64, pipeline=pipeline)
        backend.generate(VALID_STATE, self.encoded("red"), self.encoded("blue"))
        red, _, blue = pipeline.calls[0]["image"].getpixel((10, 10))
        self.assertGreater(red, 0, "original image was absent from the blended source")
        self.assertGreater(blue, 0, "previous image was absent from the blended source")

    def test_health_identifies_model_device_dimensions_and_raster_type(self):
        backend = DiffusersBackend(width=64, height=72, pipeline=self.FakePipeline(), device="test-mps")
        self.assertEqual(backend.health(), {
            "ok": True,
            "backend": "diffusers",
            "model": "stabilityai/sd-turbo",
            "device": "test-mps",
            "width": 64,
            "height": 72,
            "mediaType": "image/png",
        })


if __name__ == "__main__":
    unittest.main()

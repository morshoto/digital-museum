import io
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from visual_service.server import DiffusersBackend, diffusion_settings, model_load_source


VALID_STATE = {"brightness": .5, "warmth": .5, "abstraction": .3, "motion": .4, "tension": .2}


class DiffusionMappingTests(unittest.TestCase):
    def test_abstraction_and_motion_raise_img2img_strength(self):
        calm = diffusion_settings(dict(VALID_STATE, abstraction=.1, motion=.1), 0, turbo=True)
        active = diffusion_settings(dict(VALID_STATE, abstraction=.9, motion=.9), 0, turbo=True)
        self.assertGreater(active.strength, calm.strength)
        self.assertGreaterEqual(calm.num_inference_steps * calm.strength, 1)

    def test_turbo_uses_no_classifier_free_guidance(self):
        low = diffusion_settings(dict(VALID_STATE, tension=0), 0, turbo=True)
        high = diffusion_settings(dict(VALID_STATE, tension=1), 0, turbo=True)
        self.assertEqual(low.guidance_scale, 0)
        self.assertEqual(high.guidance_scale, 0)

    def test_original_anchor_never_falls_below_thirty_percent(self):
        settings = diffusion_settings(dict(VALID_STATE, abstraction=1), 0, turbo=True)
        self.assertGreaterEqual(settings.original_weight, .30)

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

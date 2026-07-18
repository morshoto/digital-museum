import base64
import json
import threading
import unittest
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from visual_service.server import GenerationStore, MockBackend, create_server


VALID_STATE = {"brightness": .6, "warmth": .7, "abstraction": .3, "motion": .4, "tension": .2}


class GenerationStoreTests(unittest.TestCase):
    def test_history_evicts_old_generations_at_its_limit(self):
        store = GenerationStore(limit=3)
        generation_ids = [store.put(f"image-{index}".encode()) for index in range(5)]
        self.assertIsNone(store.get(generation_ids[0]))
        self.assertIsNone(store.get(generation_ids[1]))
        self.assertEqual(store.get(generation_ids[2]), b"image-2")
        self.assertEqual(store.get(generation_ids[4]), b"image-4")

    def test_history_refreshes_recently_used_generation(self):
        store = GenerationStore(limit=2)
        first = store.put(b"first")
        second = store.put(b"second")
        self.assertEqual(store.get(first), b"first")
        third = store.put(b"third")
        self.assertEqual(store.get(first), b"first")
        self.assertIsNone(store.get(second))
        self.assertEqual(store.get(third), b"third")


class VisualServiceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = create_server(port=0, backend=MockBackend())
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.base_url = f"http://127.0.0.1:{cls.server.server_address[1]}"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def request(self, path, payload=None):
        data = json.dumps(payload).encode() if payload is not None else None
        request = Request(self.base_url + path, data=data, headers={"Content-Type": "application/json"})
        with urlopen(request, timeout=2) as response:
            return response.status, json.load(response)

    def test_health_endpoint(self):
        status, body = self.request("/health")
        self.assertEqual(status, 200)
        self.assertEqual(body, {"ok": True, "backend": "mock"})

    def test_valid_state_returns_valid_mock_image(self):
        status, body = self.request("/generate", {"state": VALID_STATE, "reference": {"originalImagePath": None, "previousGenerationID": None}})
        self.assertEqual(status, 200)
        image = base64.b64decode(body["imageBase64"])
        self.assertTrue(image.startswith(b"<svg"))
        self.assertEqual(body["mediaType"], "image/svg+xml")
        self.assertEqual(body["backend"], "mock")

    def test_previous_generation_is_accepted(self):
        _, first = self.request("/generate", {"state": VALID_STATE, "reference": {"originalImagePath": None, "previousGenerationID": None}})
        changed = dict(VALID_STATE, abstraction=.8)
        _, second = self.request("/generate", {"state": changed, "reference": {"originalImagePath": None, "previousGenerationID": first["generationID"]}})
        self.assertNotEqual(first["imageBase64"], second["imageBase64"])

    def test_out_of_range_parameter_returns_400(self):
        invalid = dict(VALID_STATE, warmth=1.2)
        with self.assertRaises(HTTPError) as context:
            self.request("/generate", {"state": invalid, "reference": {"originalImagePath": None, "previousGenerationID": None}})
        self.assertEqual(context.exception.code, 400)

    def test_malformed_request_returns_400(self):
        request = Request(self.base_url + "/generate", data=b"{nope", headers={"Content-Type": "application/json"})
        with self.assertRaises(HTTPError) as context:
            urlopen(request, timeout=2)
        self.assertEqual(context.exception.code, 400)

    def test_mock_backend_needs_no_ml_dependencies(self):
        backend = MockBackend()
        result = backend.generate(VALID_STATE, None, None)
        self.assertEqual(result.media_type, "image/svg+xml")

    def test_backend_failure_is_a_controlled_json_error(self):
        class FailingBackend:
            name = "failing"

            def health(self):
                return {"ok": True, "backend": self.name}

            def generate(self, state, original, previous):
                raise RuntimeError("intentional backend failure")

        server = create_server(port=0, backend=FailingBackend())
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        url = f"http://127.0.0.1:{server.server_address[1]}/generate"
        payload = {"state": VALID_STATE, "reference": {"originalImagePath": None, "previousGenerationID": None}}
        try:
            with self.assertRaises(HTTPError) as context:
                urlopen(Request(url, data=json.dumps(payload).encode(), headers={"Content-Type": "application/json"}), timeout=2)
            self.assertEqual(context.exception.code, 500)
            body = json.load(context.exception)
            self.assertIn("generation failed: intentional backend failure", body["error"])
        finally:
            server.shutdown()
            server.server_close()


if __name__ == "__main__":
    unittest.main()

# Local visual service

Run `python3 visual_service/server.py` from the repository root. The Swift app
posts the current `WorldState` to `http://127.0.0.1:8000/generate` every 45
seconds. The default renderer is an offline painterly SVG fallback; it exposes
the same state-to-prompt seam where a Diffusers Img2Img worker can be attached.

`GET /health` reports service availability. `POST /generate` accepts:

```json
{"state":{"brightness":0.6,"warmth":0.7,"abstraction":0.3,"motion":0.4,"tension":0.2},"previousSVG":null}
```

# Local visual service

Run `EVOLVING_BACKEND=mock python3 visual_service/server.py` from the repository
root. The Swift app posts the current `WorldState` to
`http://127.0.0.1:8000/generate` every 45 seconds. Mock mode is an offline
painterly SVG renderer with no third-party dependencies. Set
`EVOLVING_BACKEND=diffusers` and `EVOLVING_MODEL_ID` to select the optional real
Img2Img implementation.

`GET /health` reports service availability. `POST /generate` accepts:

```json
{"state":{"brightness":0.6,"warmth":0.7,"abstraction":0.3,"motion":0.4,"tension":0.2},"reference":{"originalImagePath":null,"previousGenerationID":null}}
```

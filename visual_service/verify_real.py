#!/usr/bin/env python3
"""Run two sequential HTTP generations and verify real raster responses."""
from __future__ import annotations

import argparse
import base64
import json
from pathlib import Path
import time
from urllib.request import Request, urlopen

from PIL import Image, ImageChops, ImageOps, ImageStat


STATES = (
    {"brightness": .55, "warmth": .42, "abstraction": .30, "motion": .35, "tension": .25},
    {"brightness": .68, "warmth": .72, "abstraction": .48, "motion": .62, "tension": .55},
)


def post_json(url: str, payload: dict, timeout: float) -> tuple[dict, float]:
    request = Request(url, data=json.dumps(payload).encode(), headers={"Content-Type": "application/json"})
    started = time.perf_counter()
    with urlopen(request, timeout=timeout) as response:
        return json.load(response), time.perf_counter() - started


def mean_absolute_difference(first: Image.Image, second: Image.Image) -> float:
    means = ImageStat.Stat(ImageChops.difference(first, second)).mean
    return round(sum(means) / len(means), 3)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default="http://127.0.0.1:8000")
    parser.add_argument("--original", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, default=Path("/tmp/evolving-diffusion-smoke"))
    parser.add_argument("--timeout", type=float, default=240)
    arguments = parser.parse_args()

    if not arguments.original.is_file():
        parser.error(f"original image not found: {arguments.original}")
    arguments.output_dir.mkdir(parents=True, exist_ok=True)
    previous_id = None
    records = []
    decoded = []

    for index, state in enumerate(STATES, 1):
        body, duration = post_json(
            f"{arguments.url.rstrip('/')}/generate",
            {
                "state": state,
                "reference": {
                    "originalImagePath": str(arguments.original.resolve()),
                    "previousGenerationID": previous_id,
                },
            },
            arguments.timeout,
        )
        if body.get("backend") != "diffusers" or body.get("mediaType") != "image/png":
            raise RuntimeError(f"expected a diffusers PNG response, got {body.get('backend')} {body.get('mediaType')}")
        image_bytes = base64.b64decode(body["imageBase64"], validate=True)
        output_path = arguments.output_dir / f"generation-{index}.png"
        output_path.write_bytes(image_bytes)
        with Image.open(output_path) as image:
            image.load()
            if image.format != "PNG":
                raise RuntimeError(f"generation {index} did not decode as PNG")
            decoded.append(image.convert("RGB"))
            size = image.size
            mode = image.mode
        records.append({
            "generation": index,
            "generationID": body["generationID"],
            "previousGenerationID": previous_id,
            "durationSeconds": round(duration, 3),
            "bytes": len(image_bytes),
            "size": size,
            "mode": mode,
            "path": str(output_path),
        })
        previous_id = body["generationID"]

    with Image.open(arguments.original) as source:
        original = ImageOps.fit(source.convert("RGB"), decoded[0].size, method=Image.Resampling.LANCZOS)
    print(json.dumps({
        "backend": "diffusers",
        "generations": records,
        "meanAbsolutePixelDifference": {
            "originalToGeneration1": mean_absolute_difference(original, decoded[0]),
            "originalToGeneration2": mean_absolute_difference(original, decoded[1]),
            "generation1ToGeneration2": mean_absolute_difference(decoded[0], decoded[1]),
        },
    }, indent=2))


if __name__ == "__main__":
    main()

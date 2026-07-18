#!/usr/bin/env python3
"""Run two sequential HTTP generations and verify real raster responses."""
from __future__ import annotations

import argparse
import base64
import json
from pathlib import Path
import time
from urllib.error import HTTPError
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


def get_json(url: str, timeout: float) -> dict:
    with urlopen(url, timeout=timeout) as response:
        return json.load(response)


def expect_json_error(url: str, payload: dict, timeout: float, expected_status: int) -> dict:
    try:
        post_json(url, payload, timeout)
    except HTTPError as error:
        body = json.load(error)
        if error.code != expected_status or not isinstance(body.get("error"), str):
            raise RuntimeError(f"expected HTTP {expected_status} JSON error, got HTTP {error.code}: {body}") from error
        return {"status": error.code, "error": body["error"]}
    raise RuntimeError(f"expected HTTP {expected_status}, but invalid generation succeeded")


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
    generate_url = f"{arguments.url.rstrip('/')}/generate"
    health_url = f"{arguments.url.rstrip('/')}/health"
    health_before = get_json(health_url, arguments.timeout)
    if not health_before.get("ok") or health_before.get("backend") != "diffusers" or health_before.get("mediaType") != "image/png":
        raise RuntimeError(f"expected a healthy diffusers PNG backend, got {health_before}")
    previous_id = None
    records = []
    decoded = []

    for index, state in enumerate(STATES, 1):
        body, duration = post_json(
            generate_url,
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
        expected_references = {"originalImage": True, "previousImage": previous_id is not None}
        if body.get("referenceUsage") != expected_references:
            raise RuntimeError(
                f"generation {index} reference usage was {body.get('referenceUsage')}, expected {expected_references}"
            )
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

    invalid_reference = arguments.output_dir / "invalid-reference.txt"
    invalid_reference.write_text("not an image", encoding="utf-8")
    try:
        controlled_failure = expect_json_error(
            generate_url,
            {
                "state": STATES[0],
                "reference": {
                    "originalImagePath": str(invalid_reference.resolve()),
                    "previousGenerationID": previous_id,
                },
            },
            arguments.timeout,
            expected_status=400,
        )
    finally:
        invalid_reference.unlink(missing_ok=True)
    health_after = get_json(health_url, arguments.timeout)
    if not health_after.get("ok") or health_after.get("backend") != "diffusers":
        raise RuntimeError(f"diffusers service was not healthy after controlled failure: {health_after}")

    with Image.open(arguments.original) as source:
        original = ImageOps.fit(source.convert("RGB"), decoded[0].size, method=Image.Resampling.LANCZOS)
    print(json.dumps({
        "backend": "diffusers",
        "healthBefore": health_before,
        "generations": records,
        "referenceVerification": {
            "originalUsedForEveryGeneration": True,
            "generation2UsedGeneration1": True,
        },
        "controlledFailure": controlled_failure,
        "healthAfterFailure": health_after,
        "meanAbsolutePixelDifference": {
            "originalToGeneration1": mean_absolute_difference(original, decoded[0]),
            "originalToGeneration2": mean_absolute_difference(original, decoded[1]),
            "generation1ToGeneration2": mean_absolute_difference(decoded[0], decoded[1]),
        },
    }, indent=2))


if __name__ == "__main__":
    main()

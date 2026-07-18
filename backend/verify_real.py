#!/usr/bin/env python3
"""Verify a long real-backend evolution plus controlled WorldState variants."""
from __future__ import annotations

import argparse
import base64
import json
import math
from pathlib import Path
import statistics
import time
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from PIL import Image, ImageChops, ImageFilter, ImageOps, ImageStat


DEFAULT_STATE = {
    "brightness": .55,
    "warmth": .50,
    "abstraction": .30,
    "motion": .35,
    "tension": .30,
}
CHECKPOINTS = {0, 1, 5, 10, 20}


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


def edge_correlation(first: Image.Image, second: Image.Image) -> float:
    first_values = list(first.convert("L").filter(ImageFilter.FIND_EDGES).resize((128, 72)).get_flattened_data())
    second_values = list(second.convert("L").filter(ImageFilter.FIND_EDGES).resize((128, 72)).get_flattened_data())
    first_mean = statistics.fmean(first_values)
    second_mean = statistics.fmean(second_values)
    numerator = sum((a - first_mean) * (b - second_mean) for a, b in zip(first_values, second_values))
    denominator = math.sqrt(
        sum((value - first_mean) ** 2 for value in first_values)
        * sum((value - second_mean) ** 2 for value in second_values)
    )
    return round(numerator / denominator, 4) if denominator else 0.0


def luminance(image: Image.Image) -> float:
    return round(ImageStat.Stat(image.convert("L")).mean[0], 3)


def warmth_index(image: Image.Image) -> float:
    red, _, blue = ImageStat.Stat(image).mean
    return round(red - blue, 3)


def decode_generation(body: dict, index: str, output_path: Path) -> tuple[Image.Image, int]:
    if body.get("backend") != "diffusers" or body.get("mediaType") != "image/png":
        raise RuntimeError(f"{index}: expected a diffusers PNG response")
    image_bytes = base64.b64decode(body["imageBase64"], validate=True)
    output_path.write_bytes(image_bytes)
    with Image.open(output_path) as image:
        image.load()
        if image.format != "PNG" or image.width < 64 or image.height < 64:
            raise RuntimeError(f"{index}: output was not a valid installation-size PNG")
        return image.convert("RGB"), len(image_bytes)


def contact_sheet(images: list[tuple[str, Image.Image]], output_path: Path) -> None:
    tile_width = 384
    tile_height = round(tile_width * images[0][1].height / images[0][1].width)
    sheet = Image.new("RGB", (tile_width * len(images), tile_height), "black")
    for column, (_, image) in enumerate(images):
        tile = ImageOps.fit(image, (tile_width, tile_height), method=Image.Resampling.LANCZOS)
        sheet.paste(tile, (column * tile_width, 0))
    sheet.save(output_path, format="JPEG", quality=92)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default="http://127.0.0.1:8000")
    parser.add_argument("--original", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, default=Path("/tmp/evolving-diffusion-temporal"))
    parser.add_argument("--generations", type=int, default=20)
    parser.add_argument("--timeout", type=float, default=300)
    arguments = parser.parse_args()

    if not arguments.original.is_file():
        parser.error(f"original image not found: {arguments.original}")
    if arguments.generations < 20:
        parser.error("--generations must be at least 20 for the temporal-coherence gate")
    arguments.output_dir.mkdir(parents=True, exist_ok=True)
    generate_url = f"{arguments.url.rstrip('/')}/generate"
    health_url = f"{arguments.url.rstrip('/')}/health"
    health_before = get_json(health_url, arguments.timeout)
    if not health_before.get("ok") or health_before.get("backend") != "diffusers" or health_before.get("mediaType") != "image/png":
        raise RuntimeError(f"expected a healthy diffusers PNG backend, got {health_before}")

    output_size = (health_before["width"], health_before["height"])
    with Image.open(arguments.original) as source:
        original = ImageOps.fit(source.convert("RGB"), output_size, method=Image.Resampling.LANCZOS)
    original_path = arguments.output_dir / "generation-00-original.png"
    original.save(original_path)

    previous_id = None
    records = []
    decoded = [original]
    checkpoint_images = [("generation 0", original)]
    original_resolved = True
    previous_chain_resolved = True

    for generation in range(1, arguments.generations + 1):
        body, duration = post_json(
            generate_url,
            {
                "state": DEFAULT_STATE,
                "reference": {
                    "originalImagePath": str(arguments.original.resolve()),
                    "previousGenerationID": previous_id,
                },
            },
            arguments.timeout,
        )
        usage = body.get("referenceUsage", {})
        original_resolved &= usage.get("originalImage") is True
        previous_chain_resolved &= usage.get("previousImage") is (previous_id is not None)
        output_path = arguments.output_dir / f"generation-{generation:02d}.png"
        image, byte_count = decode_generation(body, f"generation {generation}", output_path)
        decoded.append(image)
        records.append({
            "generation": generation,
            "generationID": body["generationID"],
            "previousGenerationID": previous_id,
            "durationSeconds": round(duration, 3),
            "bytes": byte_count,
            "size": image.size,
            "path": str(output_path),
        })
        previous_id = body["generationID"]
        print(
            f"verified generation {generation}/{arguments.generations} "
            f"({duration:.3f}s, {image.width}x{image.height})",
            flush=True,
        )
        if generation in CHECKPOINTS or generation == arguments.generations:
            checkpoint_images.append((f"generation {generation}", image))

    if not original_resolved or not previous_chain_resolved:
        raise RuntimeError("the real service did not resolve the complete original/previous reference chain")

    def controlled_variant(name: str, state: dict[str, float]) -> Image.Image:
        body, _ = post_json(
            generate_url,
            {
                "state": state,
                "reference": {
                    "originalImagePath": str(arguments.original.resolve()),
                    "previousGenerationID": None,
                },
            },
            arguments.timeout,
        )
        image, _ = decode_generation(body, name, arguments.output_dir / f"variant-{name}.png")
        print(f"verified controlled variant: {name}", flush=True)
        return image

    low_abstraction = controlled_variant("low-abstraction", dict(DEFAULT_STATE, abstraction=.05))
    high_abstraction = controlled_variant("high-abstraction", dict(DEFAULT_STATE, abstraction=.90))
    dark = controlled_variant("dark", dict(DEFAULT_STATE, brightness=.05))
    bright = controlled_variant("bright", dict(DEFAULT_STATE, brightness=.95))
    cool = controlled_variant("cool", dict(DEFAULT_STATE, warmth=.05))
    warm = controlled_variant("warm", dict(DEFAULT_STATE, warmth=.95))

    abstraction_metrics = {
        "lowOriginalDifference": mean_absolute_difference(original, low_abstraction),
        "highOriginalDifference": mean_absolute_difference(original, high_abstraction),
    }
    brightness_metrics = {"darkLuminance": luminance(dark), "brightLuminance": luminance(bright)}
    warmth_metrics = {"coolRedMinusBlue": warmth_index(cool), "warmRedMinusBlue": warmth_index(warm)}
    if abstraction_metrics["lowOriginalDifference"] >= abstraction_metrics["highOriginalDifference"]:
        raise RuntimeError(f"low abstraction did not preserve the source more strongly: {abstraction_metrics}")
    if brightness_metrics["brightLuminance"] - brightness_metrics["darkLuminance"] < 8:
        raise RuntimeError(f"brightness variants were not visibly separated: {brightness_metrics}")
    if warmth_metrics["warmRedMinusBlue"] - warmth_metrics["coolRedMinusBlue"] < 8:
        raise RuntimeError(f"warmth variants were not visibly separated: {warmth_metrics}")

    adjacent_differences = [
        mean_absolute_difference(decoded[index - 1], decoded[index])
        for index in range(1, len(decoded))
    ]
    original_differences = [mean_absolute_difference(original, image) for image in decoded[1:]]
    original_edge_correlations = [edge_correlation(original, image) for image in decoded[1:]]
    if mean_absolute_difference(decoded[1], decoded[-1]) < 2:
        raise RuntimeError("generation 20 did not evolve meaningfully from generation 1")

    sheet_path = arguments.output_dir / "checkpoints-0-1-5-10-20.jpg"
    contact_sheet(checkpoint_images[:5], sheet_path)

    invalid_reference = arguments.output_dir / "invalid-reference.txt"
    invalid_reference.write_text("not an image", encoding="utf-8")
    try:
        controlled_failure = expect_json_error(
            generate_url,
            {
                "state": DEFAULT_STATE,
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
        raise RuntimeError(f"diffusers service was not healthy after the long run: {health_after}")

    report = {
        "backend": "diffusers",
        "healthBefore": health_before,
        "generationParameters": DEFAULT_STATE,
        "generations": records,
        "referenceVerification": {
            "originalUsedForEveryGeneration": original_resolved,
            "completePreviousFrameChain": previous_chain_resolved,
        },
        "performance": {
            "averageSeconds": round(statistics.fmean(record["durationSeconds"] for record in records), 3),
            "medianSeconds": round(statistics.median(record["durationSeconds"] for record in records), 3),
            "minimumSeconds": min(record["durationSeconds"] for record in records),
            "maximumSeconds": max(record["durationSeconds"] for record in records),
        },
        "automatedVisualMetrics": {
            "adjacentFrameDifference": {
                "average": round(statistics.fmean(adjacent_differences), 3),
                "minimum": min(adjacent_differences),
                "maximum": max(adjacent_differences),
            },
            "originalDifference": {
                "generation1": original_differences[0],
                "generation5": original_differences[4],
                "generation10": original_differences[9],
                "generation20": original_differences[19],
            },
            "originalEdgeCorrelation": {
                "generation1": original_edge_correlations[0],
                "generation5": original_edge_correlations[4],
                "generation10": original_edge_correlations[9],
                "generation20": original_edge_correlations[19],
            },
            "abstraction": abstraction_metrics,
            "brightness": brightness_metrics,
            "warmth": warmth_metrics,
        },
        "controlledFailure": controlled_failure,
        "healthAfterFailure": health_after,
        "manualInspectionSheet": str(sheet_path),
    }
    report_path = arguments.output_dir / "report.json"
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()

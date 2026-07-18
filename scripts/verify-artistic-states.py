#!/usr/bin/env python3
"""Drive three Phase C calibration states, visuals, and continuous transitions."""

from __future__ import annotations

import argparse
import base64
import json
from pathlib import Path
import socket
import struct
import time
from urllib.request import Request, urlopen


DEFAULT_VECTORS = Path(__file__).resolve().parents[1] / "verification" / "artistic_state_vectors.json"


def calibration_vectors(path: Path) -> list[tuple[str, dict[str, float], dict[str, float]]]:
    vectors = json.loads(path.read_text())
    selected = [vector for vector in vectors if vector["name"][0:2] in {"A-", "B-", "C-"}]
    if len(selected) != 3:
        raise ValueError("shared vectors must contain exactly one A, B, and C calibration state")
    return [(vector["name"], vector["input"], vector["expected"]) for vector in selected]


def osc_string(value: str) -> bytes:
    encoded = value.encode() + b"\0"
    return encoded + b"\0" * ((-len(encoded)) % 4)


def osc_message(path: str, value: str | float) -> bytes:
    if isinstance(value, str):
        return osc_string(path) + osc_string(",s") + osc_string(value)
    return osc_string(path) + osc_string(",f") + struct.pack(">f", value)


def send_state(sock: socket.socket, target: tuple[str, int], state: dict[str, float]) -> None:
    for name, value in state.items():
        sock.sendto(osc_message(f"/{name}", value), target)


def hold_state(sock: socket.socket, target: tuple[str, int], name: str, state: dict[str, float], seconds: float) -> None:
    sock.sendto(osc_message("/verification/phase", name), target)
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        send_state(sock, target, state)
        time.sleep(.05)


def generate_visual(url: str, output: Path, original: str | None, previous: str | None, state: dict[str, float]) -> str:
    payload = {
        "state": state,
        "reference": {"originalImagePath": original, "previousGenerationID": previous},
    }
    request = Request(f"{url.rstrip('/')}/generate", data=json.dumps(payload).encode(), headers={"Content-Type": "application/json"})
    with urlopen(request, timeout=180) as response:
        result = json.load(response)
    output.write_bytes(base64.b64decode(result["imageBase64"]))
    print(f"visual={output} backend={result['backend']} id={result['generationID']} prompt={result['prompt']}", flush=True)
    return result["generationID"]


def interpolate(start: dict[str, float], end: dict[str, float], amount: float) -> dict[str, float]:
    return {name: value + (end[name] - value) * amount for name, value in start.items()}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", default=57201, type=int)
    parser.add_argument("--hold-seconds", default=8.0, type=float)
    parser.add_argument("--transition-seconds", default=8.0, type=float)
    parser.add_argument("--visual-url")
    parser.add_argument("--original")
    parser.add_argument("--output-dir", type=Path, default=Path("/tmp/evolving-phase-c-visuals"))
    parser.add_argument("--vectors", type=Path, default=DEFAULT_VECTORS)
    parser.add_argument("--no-stop", action="store_true")
    args = parser.parse_args()

    items = calibration_vectors(args.vectors)
    previous = None
    if args.visual_url:
        args.output_dir.mkdir(parents=True, exist_ok=True)
        with urlopen(f"{args.visual_url.rstrip('/')}/health", timeout=5) as response:
            suffix = ".png" if "diffus" in json.load(response)["backend"] else ".svg"
        for index, (name, state, _) in enumerate(items, 1):
            previous = generate_visual(args.visual_url, args.output_dir / f"{index}-{name}{suffix}", args.original, previous, state)

    target = (args.host, args.port)
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        for name, state, expected in items:
            print(f"phase={name} raw={state} artistic={expected}", flush=True)
            hold_state(sock, target, name, state, args.hold_seconds)

        sock.sendto(osc_message("/verification/phase", "continuous-A-B-C-A"), target)
        for (_, start, _), (_, end, _) in zip(items, items[1:] + items[:1]):
            steps = max(1, round(args.transition_seconds * 20))
            for step in range(steps):
                send_state(sock, target, interpolate(start, end, step / steps))
                time.sleep(args.transition_seconds / steps)
        if not args.no_stop:
            sock.sendto(osc_message("/verification/stop", 1.0), target)
    print("PASS: three held states and continuous A-B-C-A modulation sent without pattern commands", flush=True)


if __name__ == "__main__":
    main()

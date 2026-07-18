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


STATES = {
    "A-calm-dark": {"brightness": .15, "warmth": .20, "abstraction": .10, "motion": .10, "tension": .08},
    "B-luminous-fluid": {"brightness": .88, "warmth": .82, "abstraction": .38, "motion": .78, "tension": .18},
    "C-tense-abstract": {"brightness": .42, "warmth": .35, "abstraction": .92, "motion": .88, "tension": .90},
}


def artistic(state: dict[str, float]) -> dict[str, float]:
    return {
        "luminosity": .70 * state["brightness"] + .30 * state["warmth"],
        "fluidity": .65 * state["motion"] + .35 * state["abstraction"],
        "instability": .65 * state["tension"] + .35 * state["abstraction"],
        "serenity": 1 - (.55 * state["tension"] + .25 * state["motion"] + .20 * state["abstraction"]),
        "density": .60 * state["motion"] + .25 * state["abstraction"] + .15 * state["tension"],
    }


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
    parser.add_argument("--no-stop", action="store_true")
    args = parser.parse_args()

    previous = None
    if args.visual_url:
        args.output_dir.mkdir(parents=True, exist_ok=True)
        for index, (name, state) in enumerate(STATES.items(), 1):
            suffix = ".png" if "diffus" in json.load(urlopen(f"{args.visual_url.rstrip('/')}/health"))["backend"] else ".svg"
            previous = generate_visual(args.visual_url, args.output_dir / f"{index}-{name}{suffix}", args.original, previous, state)

    target = (args.host, args.port)
    items = list(STATES.items())
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        for name, state in items:
            print(f"phase={name} raw={state} artistic={artistic(state)}", flush=True)
            hold_state(sock, target, name, state, args.hold_seconds)

        sock.sendto(osc_message("/verification/phase", "continuous-A-B-C-A"), target)
        for (_, start), (_, end) in zip(items, items[1:] + items[:1]):
            steps = max(1, round(args.transition_seconds * 20))
            for step in range(steps):
                send_state(sock, target, interpolate(start, end, step / steps))
                time.sleep(args.transition_seconds / steps)
        if not args.no_stop:
            sock.sendto(osc_message("/verification/stop", 1.0), target)
    print("PASS: three held states and continuous A-B-C-A modulation sent without pattern commands", flush=True)


if __name__ == "__main__":
    main()

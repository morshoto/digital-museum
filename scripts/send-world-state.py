#!/usr/bin/env python3
"""Send a deterministic independent-parameter WorldState sequence over OSC."""

from __future__ import annotations

import argparse
import socket
import struct
import time


PARAMETERS = ("brightness", "warmth", "abstraction", "motion", "tension")


def osc_string(value: str) -> bytes:
    encoded = value.encode("utf-8") + b"\0"
    return encoded + (b"\0" * ((-len(encoded)) % 4))


def osc_message(path: str, *arguments: object) -> bytes:
    tags = [","]
    payload = []
    for argument in arguments:
        if isinstance(argument, str):
            tags.append("s")
            payload.append(osc_string(argument))
        elif isinstance(argument, float):
            tags.append("f")
            payload.append(struct.pack(">f", argument))
        else:
            raise TypeError(f"unsupported OSC argument: {argument!r}")
    return osc_string(path) + osc_string("".join(tags)) + b"".join(payload)


def send(sock: socket.socket, target: tuple[str, int], path: str, *arguments: object) -> None:
    sock.sendto(osc_message(path, *arguments), target)


def send_state(
    sock: socket.socket,
    target: tuple[str, int],
    selected: str,
    value: float,
    hold_seconds: float,
) -> None:
    phase = f"{selected}={value:.0f}"
    send(sock, target, "/verification/phase", phase)
    state = {parameter: 0.5 for parameter in PARAMETERS}
    state[selected] = value
    deadline = time.monotonic() + hold_seconds
    while time.monotonic() < deadline:
        for parameter, parameter_value in state.items():
            send(sock, target, f"/{parameter}", float(parameter_value))
        time.sleep(0.05)
    print(f"sent {phase}; other parameters=0.5", flush=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", default=57120, type=int)
    parser.add_argument("--hold-seconds", default=8.0, type=float)
    parser.add_argument("--no-stop", action="store_true")
    args = parser.parse_args()

    target = (args.host, args.port)
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        for parameter in PARAMETERS:
            for value in (0.0, 1.0):
                send_state(sock, target, parameter, value, args.hold_seconds)
        if not args.no_stop:
            send(sock, target, "/verification/stop")


if __name__ == "__main__":
    main()

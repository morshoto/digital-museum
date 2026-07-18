#!/usr/bin/env python3
"""Verify independent WorldState effects in live /dirt/play traffic."""

from __future__ import annotations

import argparse
import select
import socket
import struct
import time
from collections import defaultdict


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


def read_string(packet: bytes, offset: int) -> tuple[str, int]:
    end = packet.index(0, offset)
    value = packet[offset:end].decode("utf-8")
    return value, (end + 4) & ~3


def parse_message(packet: bytes) -> tuple[str, dict[str, object]]:
    path, offset = read_string(packet, 0)
    tags, offset = read_string(packet, offset)
    values = []
    for tag in tags[1:]:
        if tag == "s":
            value, offset = read_string(packet, offset)
        elif tag == "f":
            value = struct.unpack_from(">f", packet, offset)[0]
            offset += 4
        elif tag == "i":
            value = struct.unpack_from(">i", packet, offset)[0]
            offset += 4
        elif tag == "d":
            value = struct.unpack_from(">d", packet, offset)[0]
            offset += 8
        else:
            raise ValueError(f"unsupported OSC type tag: {tag}")
        values.append(value)
    return path, dict(zip(values[::2], values[1::2], strict=True))


def parse_packet(packet: bytes) -> list[tuple[str, dict[str, object]]]:
    if not packet.startswith(b"#bundle\0"):
        return [parse_message(packet)]
    messages = []
    offset = 16  # '#bundle\0' plus the eight-byte timetag
    while offset < len(packet):
        size = struct.unpack_from(">i", packet, offset)[0]
        offset += 4
        messages.extend(parse_packet(packet[offset : offset + size]))
        offset += size
    return messages


def nearly(value: object, expected: float) -> bool:
    return isinstance(value, (int, float)) and abs(value - expected) < 0.001


def assert_control(events: list[dict[str, object]], name: str, expected: float) -> None:
    values = [event[name] for event in events if name in event]
    if not values or not all(nearly(value, expected) for value in values):
        raise AssertionError(f"expected {name}={expected}, saw {sorted(set(values))}")


def sound_gains(events: list[dict[str, object]]) -> dict[str, set[float]]:
    result: dict[str, set[float]] = defaultdict(set)
    for event in events:
        if "s" in event and "gain" in event:
            result[str(event["s"])].add(round(float(event["gain"]), 3))
    return dict(result)


def collect_phase(
    receiver: socket.socket,
    sender: socket.socket,
    bridge: tuple[str, int],
    selected: str,
    value: float,
    seconds: float,
) -> list[dict[str, object]]:
    state = {parameter: 0.5 for parameter in PARAMETERS}
    state[selected] = value
    started = time.monotonic()
    deadline = started + seconds
    events = []
    while time.monotonic() < deadline:
        for parameter, parameter_value in state.items():
            sender.sendto(osc_message(f"/{parameter}", float(parameter_value)), bridge)
        readable, _, _ = select.select([receiver], [], [], 0.05)
        if readable:
            packet, _ = receiver.recvfrom(65535)
            for path, event in parse_packet(packet):
                if path == "/dirt/play" and time.monotonic() - started > 0.5:
                    events.append(event)
    return events


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bridge-port", default=57201, type=int)
    parser.add_argument("--dirt-port", default=57200, type=int)
    parser.add_argument("--phase-seconds", default=5.0, type=float)
    args = parser.parse_args()

    phases: dict[tuple[str, int], list[dict[str, object]]] = {}
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as receiver, socket.socket(
        socket.AF_INET, socket.SOCK_DGRAM
    ) as sender:
        receiver.bind(("127.0.0.1", args.dirt_port))
        receiver.setblocking(False)
        bridge = ("127.0.0.1", args.bridge_port)
        for parameter in PARAMETERS:
            for value in (0, 1):
                events = collect_phase(
                    receiver,
                    sender,
                    bridge,
                    parameter,
                    float(value),
                    args.phase_seconds,
                )
                phases[(parameter, value)] = events
                print(f"{parameter}={value}: {len(events)} /dirt/play events")

    assert_control(phases[("brightness", 0)], "cutoff", 650.0)
    assert_control(phases[("brightness", 1)], "cutoff", 12000.0)

    warmth_low = sound_gains(phases[("warmth", 0)])
    warmth_high = sound_gains(phases[("warmth", 1)])
    expected_warmth = {
        "superpiano": (0.13, 0.52),
        "arpy": (0.52, 0.13),
        "bd": (0.28, 0.52),
        "hh": (0.44, 0.08),
        "cp": (0.12, 0.24),
    }
    for sound, (low, high) in expected_warmth.items():
        if not any(nearly(value, low) for value in warmth_low.get(sound, set())):
            raise AssertionError(f"warmth=0 missing {sound} gain {low}: {warmth_low}")
        if not any(nearly(value, high) for value in warmth_high.get(sound, set())):
            raise AssertionError(f"warmth=1 missing {sound} gain {high}: {warmth_high}")

    low_notes = [
        (event.get("s"), event.get("n"))
        for event in phases[("abstraction", 0)]
        if event.get("orbit") == 0
    ]
    high_notes = [
        (event.get("s"), event.get("n"))
        for event in phases[("abstraction", 1)]
        if event.get("orbit") == 0
    ]
    if len(low_notes) < 4 or len(high_notes) < 4 or low_notes == high_notes:
        raise AssertionError("abstraction did not produce distinct pitched event ordering")

    motion_low = len(phases[("motion", 0)])
    motion_high = len(phases[("motion", 1)])
    if motion_low == 0 or motion_high / motion_low < 2.5:
        raise AssertionError(f"motion density ratio too small: {motion_high}/{motion_low}")

    assert_control(phases[("tension", 0)], "crush", 16.0)
    assert_control(phases[("tension", 1)], "crush", 5.0)
    assert_control(phases[("tension", 0)], "detune", 0.0)
    assert_control(phases[("tension", 1)], "detune", 0.42)
    assert_control(phases[("tension", 0)], "nudge", 0.0)
    assert_control(phases[("tension", 1)], "nudge", 0.09)

    print(f"brightness cutoff: 650.0 -> 12000.0")
    print(f"warmth gains: {warmth_low} -> {warmth_high}")
    print(f"abstraction pitched order: {low_notes} -> {high_notes}")
    print(f"motion event ratio: {motion_high}/{motion_low} = {motion_high / motion_low:.2f}")
    print("tension: detune 0.0 -> 0.42, nudge 0.0 -> 0.09, crush 16.0 -> 5.0")
    print("PASS: five independent controls changed running Tidal /dirt/play output")


if __name__ == "__main__":
    main()

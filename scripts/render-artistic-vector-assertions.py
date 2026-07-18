#!/usr/bin/env python3
"""Render GHCi assertions for Tidal's artistic-state pure functions."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def literal(value: float) -> str:
    return repr(float(value))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("vectors", type=Path)
    args = parser.parse_args()
    vectors = json.loads(args.vectors.read_text())
    checks = []
    for vector in vectors:
        raw = vector["input"]
        expected = vector["expected"]
        checks.extend([
            f"abs (artisticLuminosity {literal(raw['brightness'])} {literal(raw['warmth'])} - {literal(expected['luminosity'])}) < 1e-9",
            f"abs (artisticFluidity {literal(raw['motion'])} {literal(raw['abstraction'])} - {literal(expected['fluidity'])}) < 1e-9",
            f"abs (artisticInstability {literal(raw['tension'])} {literal(raw['abstraction'])} - {literal(expected['instability'])}) < 1e-9",
            f"abs (artisticSerenity {literal(raw['tension'])} {literal(raw['motion'])} {literal(raw['abstraction'])} - {literal(expected['serenity'])}) < 1e-9",
            f"abs (artisticDensity {literal(raw['motion'])} {literal(raw['abstraction'])} {literal(raw['tension'])} - {literal(expected['density'])}) < 1e-9",
        ])
    print(
        "if and [" + ", ".join(checks) + "] "
        f'then putStrLn "PASS: Tidal artistic-state functions match {len(vectors)} shared golden vectors" '
        'else error "Tidal artistic-state functions drifted from shared golden vectors"'
    )


if __name__ == "__main__":
    main()

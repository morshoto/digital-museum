#!/usr/bin/env python3
"""Write and read operator runtime state without evaluating shell content."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import tempfile


FIELDS = (
    "visual_pid",
    "supercollider_pid",
    "scsynth_pid",
    "tidal_pid",
    "tidal_keepalive_pid",
    "app_pid",
    "runtime_backend",
    "runtime_visual_url",
    "runtime_require_music",
    "runtime_log_dir",
    "runtime_started_at",
)


def write_state(args: argparse.Namespace) -> None:
    destination = Path(args.path)
    destination.parent.mkdir(parents=True, exist_ok=True)
    state = {field: getattr(args, field) for field in FIELDS}
    state["version"] = 1
    descriptor, temporary_name = tempfile.mkstemp(
        dir=destination.parent, prefix=f".{destination.name}.", text=True
    )
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as output:
            json.dump(state, output, indent=2, sort_keys=True)
            output.write("\n")
        os.replace(temporary_name, destination)
    except BaseException:
        try:
            os.close(descriptor)
        except OSError:
            pass
        Path(temporary_name).unlink(missing_ok=True)
        raise


def get_value(args: argparse.Namespace) -> None:
    with Path(args.path).open(encoding="utf-8") as source:
        state = json.load(source)
    if state.get("version") != 1:
        raise SystemExit("unsupported runtime state version")
    value = state.get(args.key, "")
    if not isinstance(value, str):
        raise SystemExit(f"runtime state field {args.key!r} is not a string")
    print(value)


def main() -> None:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    writer = subparsers.add_parser("write")
    writer.add_argument("path")
    for field in FIELDS:
        writer.add_argument(f"--{field.replace('_', '-')}", default="")
    writer.set_defaults(handler=write_state)
    reader = subparsers.add_parser("get")
    reader.add_argument("path")
    reader.add_argument("key", choices=FIELDS)
    reader.set_defaults(handler=get_value)
    args = parser.parse_args()
    args.handler(args)


if __name__ == "__main__":
    main()

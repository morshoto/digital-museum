#!/usr/bin/env python3
"""Fail when configured TCP/UDP listener ports cannot be reserved locally."""

from __future__ import annotations

import argparse
import socket


def check(value: str, socket_type: socket.SocketKind) -> None:
    host, raw_port = value.rsplit(":", 1)
    with socket.socket(socket.AF_INET, socket_type) as listener:
        listener.bind((host, int(raw_port)))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tcp", action="append", default=[])
    parser.add_argument("--udp", action="append", default=[])
    args = parser.parse_args()
    failures = []
    for kind, values in ((socket.SOCK_STREAM, args.tcp), (socket.SOCK_DGRAM, args.udp)):
        for value in values:
            try:
                check(value, kind)
            except (OSError, OverflowError, ValueError) as error:
                failures.append(f"{value}: {error}")
    if failures:
        raise SystemExit("port unavailable: " + "; ".join(failures))


if __name__ == "__main__":
    main()

# ADR 0001: Continuous Diffusion stream

- Status: Accepted
- Date: 2026-07-18

This decision is extended by [ADR 0002](0002-impressionist-painting-worlds.md),
which adds long-period reference worlds and further reduces presentation motion.

## Context

Long Diffusion intervals made Swift opacity, scale, and position changes carry
most of the visible motion. The result could read as a camera moving over a
static painting rather than the painting itself evolving. The installed SDXL
Turbo pipeline remains warm and has demonstrated enough MPS throughput for a
five-second generation cadence without adding StreamDiffusion's CUDA-oriented
runtime.

## Decision

Use the existing persistent SDXL Turbo service as a continuous, one-frame
generation engine:

```text
next frame = Diffusion(previous valid frame, original painting, latest WorldState)
```

Swift starts at most one generation every five seconds. It never queues work;
if inference is still active, that interval is skipped and the following start
uses the newest `WorldState`. Each successful result becomes both the next
display frame and the feedback reference. A failed request leaves the last
valid display and feedback reference unchanged.

Per-generation strength is reduced and capped at `0.42`. The existing
continuous original anchor and output re-anchor remain, while the 10% periodic
pullback moves from every 5 generations to every 18 generations. Swift blends
frames for 1.2 seconds. ADR 0002 subsequently narrows auxiliary movement from
this decision's initial `1.00...1.005` scale and two-point translation limits.

The public HTTP request and response, `WorldState` transport, and audio paths do
not change.

## Consequences

- Real Diffusion evolution becomes the primary visible motion approximately
  every five seconds.
- The warm pipeline and non-overlap gate keep memory and latency predictable;
  no frame queue can grow during a slow inference.
- Twelve generations per minute increase cumulative drift pressure, so each
  step is smaller and periodic pullback occurs about every 90 seconds.
- Apple Silicon remains on the verified MPS implementation. StreamDiffusion or
  similarity-based skipping can be evaluated later without changing this
  contract.

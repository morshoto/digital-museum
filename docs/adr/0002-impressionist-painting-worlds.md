# ADR 0002: Impressionist painting worlds

- Status: Accepted
- Date: 2026-07-18

## Context

The five-second continuous Diffusion stream made generated change frequent, but
one permanent Monet anchor limited the installation to a single visual world.
Increasing Swift pan and zoom would add camera motion rather than artistic
variety. Switching complete source images would instead read as a slideshow.

## Decision

Bundle a shared, versioned catalog of eight public-domain Impressionist
paintings spanning Monet, Renoir, Pissarro, Sisley, and Morisot. Each profile
contains provenance, semantic tags, a bounded default-state bias, palette,
brush and structure language, and prompt subjects.

Swift owns the long painting-world timeline independently of the five-second
generation scheduler. A world remains settled for a deterministic 24–96
successful generations (two to eight minutes). The next profile is selected by
a stable rotation that avoids the same artist consecutively. Six subsequent
generations move the original anchor through a smootherstep blend from the
current painting to the target. The previous generated frame remains the
feedback input throughout that bridge.

Anchor compositing runs only for those six bridge generations and produces a
1024×576 PNG using AppKit. Settled generations use the bundled source file
directly. The visual service resolves the shared catalog beside bundled source
files and uses the bridge filename's catalog indices to apply both profiles'
prompt language. Its state bias is 12% by default and hard-capped at 20%; the
transported WorldState and audio state remain unchanged.
The bridge directory carries the same catalog so a service restart during a
transition can recover profile context from its first request.

SDXL Turbo's CLIP encoder truncates prompts beyond 77 tokens. Profile language
therefore appears first and the complete prompt is deliberately compact. The
real tokenizer test covers every settled profile, adjacent bridge, progress
step, and state extreme; the current maximum is 74 tokens.

Painting-world advancement is committed only after a response contains a
valid decoded image. Failures retain both the last generated frame and the
current anchor state. Revision tokens prevent an obsolete completion from
advancing a newer world.

Swift presentation remains a 1.2-second crossfade. Optional motion is reduced
to `1.000...1.002` scale and at most one point of translation; zero motion
produces no transform.

The public Swift-to-service HTTP schema, WorldState transport, and TidalCycles
and SuperCollider behavior do not change.

## Consequences

- Diffusion remains the source of visible evolution at the five-second scale.
- Artistic variety changes at a separate two-to-eight-minute scale without a
  hard source-image cut.
- The catalog is a single source of truth shared by Swift resource validation
  and Python prompt interpretation.
- Four additional CC0/public-domain image assets increase the application
  bundle and repository size.
- Anchor raster work occurs at most six times per world change, not every
  display frame or every settled Diffusion generation.

# Shared artistic state

Phase C keeps the five normalized `WorldState` fields and their OSC addresses
as the compatibility and transport contract. Visuals and music derive the same
five higher-level qualities locally. No derived field adds an OSC path, changes
the visual HTTP request, or introduces independent randomness.

`abstraction` retains one privileged visual responsibility: it is the hard
limit on how far Diffusion may depart from the source painting. The derived
qualities determine how change appears inside that allowance:

```text
abstraction -> allowed visual divergence
fluidity / instability / serenity / density -> character of that divergence
```

## Current mapping audit

Before this phase, the visual service mapped `brightness` to source exposure
and prompt light, `warmth` to red/blue balance and palette language,
`abstraction` to Img2Img strength/original anchoring and stroke count,
`motion` to Img2Img strength, stroke scale, and Tidal pattern speed, and
`tension` to contrast, guidance, detune, nudge, and bit crushing. Tidal also
used brightness for its low-pass cutoff, warmth for a constant-sum voice
crossfade, and abstraction for probabilistic motif reordering.

All five paths produced measurable output, but the relationships were mostly
parallel one-to-one controls. Brightness was perceptually strong because both
light and filter cutoff opened together. Motion was strong because visual
marks grew while event rate rose. Warmth was weaker: visual temperature and an
instrument gain crossfade can read as unrelated unless light supports them.
Abstraction was weak across media because visual denoising strength and motif
reordering have no obvious common gesture. Tension was technically strong but
could sound like degradation while looking only like contrast. The new layer
combines these raw values into shared qualities that can drive several related
controls in each medium.

## Deterministic model

For normalized raw values `b` (brightness), `w` (warmth), `a` (abstraction),
`m` (motion), and `t` (tension):

```text
luminosity  = 0.70b + 0.30w
fluidity    = 0.65m + 0.35a
instability = 0.65t + 0.35a
serenity    = 1 - (0.55t + 0.25m + 0.20a)
density     = 0.60m + 0.25a + 0.15t
```

Every expression is a convex combination (or one minus one), so normalized
inputs always produce values in `0...1`. The same input always produces the
same output. Swift, Python, and Tidal implement the equations at their existing
consumer boundaries. All three are checked against
[`../verification/artistic_state_vectors.json`](../verification/artistic_state_vectors.json)
so a unilateral formula edit fails verification instead of silently separating
the media.

## Visual mapping

| Quality | Existing visual controls | Intended perception |
| --- | --- | --- |
| Luminosity | Source exposure, prompt light, mock sky light | Shared radiant or subdued world light |
| Fluidity | Img2Img strength, prompt gesture, mock stroke scale and blur | Flowing deformation rather than mere activity |
| Instability | Img2Img strength, non-turbo guidance, source contrast, prompt structure | Structural disturbance and contrast |
| Serenity | Original-image blend and composition-preservation language | Calm states retain composition more strongly |
| Density | Non-turbo steps, prompt texture, mock stroke count | Sparse versus layered visual texture |

Raw `warmth` still controls precise red/blue temperature, and all five raw
values remain in the unchanged request. Sequence remains part of Diffusion's
seed so successive frames can evolve; artistic variation is still conditioned
on the deterministic shared state.

Diffusion strength and source anchoring apply the following additional
constraints:

```text
base_strength = 0.25 + 0.18 * abstraction
modifier = 0.03 * fluidity + 0.02 * instability
strength_cap = 0.30 + 0.19 * abstraction
strength = min(0.49, strength_cap, base_strength + modifier)

abstraction_anchor = interpolate(configured_low, configured_high, abstraction)
original_weight = min(0.90, abstraction_anchor + 0.04 * serenity)
```

Consequently, `abstraction = 0` caps strength at `0.30` and retains at least
the configured low-abstraction anchor (72% by default) even when motion and
tension are both maximal. The visual-coherence layer also applies its periodic
pull-back and bounded post-generation original blend; derived qualities cannot
weaken either abstraction-based constraint.

## Music mapping

| Quality | Tidal controls | Intended perception |
| --- | --- | --- |
| Luminosity | `lpf` | Brighter states open the spectrum |
| Fluidity | `room`, `size`, and its contribution to density | More connected, spacious rhythmic flow |
| Instability | `sometimesBy (iter 4)`, `detune`, `nudge`, `crush` | Mutated motifs, syncopation, and rough harmonic color |
| Serenity | `legato` | Calm states sustain and connect pitched events |
| Density | `fast` on both running patterns | Sparse versus active event structure |

Raw `warmth` retains the compatible constant-sum instrument/percussion balance.
All controls are pattern-valued `cF` expressions. `d1` and `d2` are
evaluated once; changing state never stops or replaces them.

## Response strategy

Swift continues sending raw OSC state at approximately 10 Hz. Tidal reads the
latest controls inside its continuously running patterns, so audible response
arrives over the next events and cycles (roughly sub-second to several
seconds). The visual service samples the same world only when generating a new
frame, normally every 45 seconds, and Swift crossfades valid frames. Thus both
media inhabit the same state trajectory while music articulates short changes
and visuals integrate a slower snapshot instead of moving in lockstep.

## Contrasting tuning states

| State | Raw values `(b,w,a,m,t)` | Derived `(lum,fluid,instab,serene,dense)` | Intended shared character |
| --- | --- | --- | --- |
| A calm/dark | `(0.15,0.20,0.10,0.10,0.08)` | `(0.165,0.100,0.087,0.911,0.097)` | Dark, sparse, compositionally stable, sustained |
| B luminous/fluid | `(0.88,0.82,0.38,0.78,0.18)` | `(0.862,0.640,0.250,0.630,0.590)` | Warm light, flowing marks, open spectrum, active but consonant |
| C tense/abstract | `(0.42,0.35,0.92,0.88,0.90)` | `(0.399,0.894,0.907,0.101,0.893)` | Dense deformation, fractured rhythm, low serenity, strong disturbance |

These are deliberate calibration anchors, not discrete scenes. Exhibition
operation should modulate continuously between and beyond them.

The Phase C runtime evidence and exact reproduction procedure are recorded in
[`PHASE_C_VERIFICATION.md`](PHASE_C_VERIFICATION.md).

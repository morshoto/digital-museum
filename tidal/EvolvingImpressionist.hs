-- Evaluate in a normal TidalCycles session. WorldStateBridge.scd forwards the
-- five Swift OSC paths to Tidal's native /ctrl input on port 6010. `cF` and
-- `cT` read the latest values without replacing or restarting these patterns.

setcps (112/60/4)

let worldBrightness  = cF 0.5 "brightness"
    worldWarmth      = cF 0.5 "warmth"
    worldAbstraction = cF 0.3 "abstraction"
    worldMotion      = cF 0.4 "motion"
    worldTension     = cF 0.2 "tension"

-- These are the same bounded deterministic artistic-state equations used by
-- Swift and the visual service. The bridge remains compatible: only the five
-- original controls cross OSC, and Tidal derives these continuously.
    worldLuminosity  = 0.70 * worldBrightness + 0.30 * worldWarmth
    worldFluidity    = 0.65 * worldMotion + 0.35 * worldAbstraction
    worldInstability = 0.65 * worldTension + 0.35 * worldAbstraction
    worldSerenity    = 1 - (0.55 * worldTension + 0.25 * worldMotion + 0.20 * worldAbstraction)
    worldDensity     = 0.60 * worldMotion + 0.25 * worldAbstraction + 0.15 * worldTension

-- Luminosity opens the spectrum; fluidity changes
-- phrasing; instability mutates the motif. Raw warmth retains its compatible
-- continuous timbral crossfade.
d1 $ fast (fmap toRational (range 0.70 1.65 worldDensity))
   $ sometimesBy worldInstability (iter 4)
   $ stack
      [ slow 2 $ n (scale "minor" "0 2 4 6") # s "superpiano"
          # gain (range 0.13 0.52 worldWarmth)
      , slow 4 $ n (scale "minor" "7 4 2 9") # s "arpy"
          # gain (range 0.52 0.13 worldWarmth)
      ]
   # lpf (range 650 12000 worldLuminosity)
   # legato (range 0.65 1.55 worldSerenity)
   # room (range 0.08 0.42 worldFluidity)
   # size (range 0.20 0.75 worldFluidity)
   # detune (range 0 0.42 worldInstability)
   # crush (range 16 5 worldInstability)

-- Density controls rhythmic activity; instability adds syncopation and rough
-- resolution while the stable polymeter continues without pattern restarts.
d2 $ fast (fmap toRational (range 0.55 2.20 worldDensity))
   $ sometimesBy worldInstability (iter 4)
   $ stack
      [ s "bd*2" # gain (range 0.28 0.52 worldWarmth)
      , s "~ hh*8" # gain (range 0.44 0.08 worldWarmth)
      , every 7 rev $ s "~ cp ~ cp" # gain (range 0.12 0.24 worldWarmth)
      ]
   # lpf (range 650 12000 worldLuminosity)
   # room (range 0.04 0.28 worldFluidity)
   # nudge (range 0 0.09 worldInstability)
   # crush (range 16 5 worldInstability)

-- Stop manually when leaving the installation session:
-- hush

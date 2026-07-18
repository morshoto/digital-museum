-- Load this file in a TidalCycles session after starting SuperDirt.
-- The Swift app sends /brightness, /warmth, /abstraction, /motion, /tension
-- as OSC floats to port 57120. Use an OSC bridge or your preferred Tidal
-- controller to bind those messages to these shared controls.

setcps (130/60/4)

let worldBrightness = pF "brightness" (range 0.2 1.0 $ sine)
    worldWarmth     = pF "warmth"     (range 0.0 1.0 $ sine)
    worldMotion     = pF "motion"     (range 0.15 1.0 $ sine)
    worldTension    = pF "tension"    (range 0.0 1.0 $ sine)

d1 $ sometimesBy 0.25 (rev) $
  n (irand 7)
  # s "superpiano"
  # scale "minor"
  # room 0.7
  # lpf (worldBrightness * 5000 + 800)
  # gain (worldMotion * 0.18 + 0.18)

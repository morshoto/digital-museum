-- Evaluate in a normal TidalCycles session. WorldStateBridge.scd forwards the
-- five Swift OSC paths to Tidal's native /ctrl input on port 6010. `cF` and
-- `cT` read the latest values without replacing or restarting these patterns.

setcps (112/60/4)

let worldBrightness  = cF 0.5 "brightness"
    worldWarmth      = cF 0.5 "warmth"
    worldAbstraction = cF 0.3 "abstraction"
    worldMotion      = cT 0.4 "motion"
    worldTension     = cF 0.2 "tension"

-- brightness opens the filter; warmth continuously crossfades two timbres;
-- abstraction increases the probability of four-step motif re-ordering;
-- motion changes event density by scaling pattern time.
d1 $ fast (range 0.55 2.2 worldMotion)
   $ sometimesBy worldAbstraction (iter 4)
   $ stack
      [ slow 2 $ n (scale "minor" "0 2 4 6") # s "superpiano"
          # legato 1.4
          # lpf (range 650 12000 worldBrightness)
          # gain (range 0.13 0.52 worldWarmth)
      , slow 4 $ n (scale "minor" "7 4 2 9") # s "arpy"
          # lpf (range 650 12000 worldBrightness)
          # gain (range 0.52 0.13 worldWarmth)
      ]
   # detune (range 0 0.42 worldTension)
   # crush (range 16 5 worldTension)

-- motion also changes rhythmic density. Tension adds syncopated timing drift
-- and progressively rough resolution while the stable polymeter keeps going.
d2 $ fast (range 0.55 2.2 worldMotion)
   $ sometimesBy worldAbstraction (iter 4)
   $ stack
      [ s "bd*2" # gain (range 0.28 0.52 worldWarmth)
      , s "~ hh*8" # gain (range 0.44 0.08 worldWarmth)
      , every 7 rev $ s "~ cp ~ cp" # gain (range 0.12 0.24 worldWarmth)
      ]
   # lpf (range 650 12000 worldBrightness)
   # nudge (range 0 0.09 worldTension)
   # crush (range 16 5 worldTension)

-- Stop manually when leaving the installation session:
-- hush

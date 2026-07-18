-- Evaluate after SuperDirt.start and WorldStateBridge.scd.
-- The Swift app sends WorldState directly to SuperCollider on 57120. The
-- bridge maps it continuously while these Tidal layers keep playing.

setcps (112/60/4)

-- Stable motif: brightness and warmth are applied by the SC world layer.
d1 $ slow 2 $ n "0 2 4 6" # scale "minor" # s "superpiano"
  # legato 1.4 # room 0.55 # gain 0.72

-- A gently polymetric rhythm gives abstraction/motion room to be heard in the
-- shared world layer without stopping or replacing the composition.
d2 $ stack
  [ s "bd*2" # gain 0.75
  , s "~ hh*5" # gain 0.34
  , every 7 (rev) $ s "~ cp ~ cp" # gain 0.28
  ]

-- Stop manually when leaving the installation session:
-- hush

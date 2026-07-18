// Run after SuperDirt.start. The app sends OSC floats to language port 57120.
// This audible companion layer demonstrates all five continuous mappings while
// Tidal's patterns in EvolvingImpressionist.hs continue without restarts.
(
~world = (brightness: 0.5, warmth: 0.5, abstraction: 0.3, motion: 0.4, tension: 0.2);

SynthDef(\evolvingWorld, { |out=0, brightness=0.5, warmth=0.5, abstraction=0.3, motion=0.4, tension=0.2|
    var density = LinExp.kr(motion, 0, 1, 0.7, 9);             // event density
    var trigger = Dust.kr(density);
    var pitch = TIRand.kr(0, 7 + (abstraction * 14), trigger); // pattern complexity
    var base = 38 + (brightness * 34);                         // pitch range
    var detune = TRand.kr(0, tension * 3.5, trigger);           // dissonance
    var frequency = (base + pitch + detune).midicps;
    var metallic = Ringz.ar(trigger, frequency * [1, 1.005], 0.2 + warmth);
    var soft = SinOsc.ar(frequency * [1, 1.002]) * Decay2.kr(trigger, 0.01, 0.4 + warmth);
    var timbre = XFade2.ar(metallic, soft, warmth.linlin(0, 1, -1, 1)); // warm/cold balance
    var cutoff = LinExp.kr(brightness, 0, 1, 500, 9000);        // filter brightness
    var unstable = DelayC.ar(timbre, 0.08, LFNoise1.kr(3).range(0, tension * 0.08));
    Out.ar(out, Limiter.ar(LPF.ar(timbre + unstable, cutoff) * 0.14));
}).add;

s.sync;
~worldSynth = Synth(\evolvingWorld);

[\brightness, \warmth, \abstraction, \motion, \tension].do { |name|
    OSCdef(("world_" ++ name).asSymbol, { |message|
        var value = message[1].asFloat.clip(0, 1);
        ~world[name] = value;
        ~worldSynth.set(name, value);
        ("WorldState " ++ name ++ " = " ++ value.round(0.001)).postln;
    }, "/" ++ name);
};
)

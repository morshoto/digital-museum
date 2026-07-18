// Live audio/OSC trace harness. Start this with sclang, then start Tidal and
// run scripts/send-world-state.py. The deterministic sender drives the same
// five OSC paths as Swift while this process runs SuperDirt and records output.
(
var bridgePath = thisProcess.nowExecutingPath.dirname +/+ "WorldStateBridge.scd";
var recordingPath = "EVOLVING_AUDIO_RECORDING".getenv
    ? "/tmp/evolving-impressionist-live.wav";
var dirtPort = ("EVOLVING_DIRT_PORT".getenv ? "57120").asInteger;

~verificationPhase = "startup";
~dirtEventCount = 0;

s.options.numBuffers = 1024 * 256;
s.options.memSize = 8192 * 32;
s.options.numWireBufs = 2048;
s.options.maxNodes = 1024 * 32;
s.options.numOutputBusChannels = 2;
s.options.numInputBusChannels = 2;

s.waitForBoot {
    ~dirt = SuperDirt(2, s);
    ~dirt.loadSoundFiles;
    s.sync;
    ~dirt.start(dirtPort, [0, 0]);
    SuperDirt.default = ~dirt;

    bridgePath.load;

    OSCdef(\evolving_verification_phase).free;
    OSCdef(\evolving_verification_phase, { |message|
        ~verificationPhase = message[1].asString;
        ("PHASE " ++ ~verificationPhase).postln;
    }, "/verification/phase");

    OSCdef(\evolving_dirt_trace).free;
    OSCdef(\evolving_dirt_trace, { |message|
        var event = ();
        (1, 3 .. (message.size - 2)).do { |index|
            event[message[index].asString.asSymbol] = message[index + 1];
        };
        ~dirtEventCount = ~dirtEventCount + 1;
        [
            "DIRT",
            ~dirtEventCount,
            ~verificationPhase,
            ~worldState.copy,
            event
        ].asCompileString.postln;
    }, "/dirt/play");

    OSCdef(\evolving_verification_stop).free;
    OSCdef(\evolving_verification_stop, {
        "LIVE_VERIFY_STOPPING".postln;
        s.stopRecording;
        Routine({
            1.wait;
            ("LIVE_VERIFY_EVENTS " ++ ~dirtEventCount).postln;
            0.exit;
        }).play(AppClock);
    }, "/verification/stop");

    s.record(recordingPath, 0, 2);
    ("LIVE_VERIFY_RECORDING " ++ recordingPath).postln;
    ("LIVE_VERIFY_READY dirtPort=" ++ dirtPort ++ " langPort=" ++ NetAddr.langPort).postln;
};

s.boot;
)

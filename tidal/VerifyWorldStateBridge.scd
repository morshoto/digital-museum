// Headless, non-audio verification for WorldStateBridge.scd. It opens Tidal's
// default control port locally and confirms the real sclang forwarding path.
(
var bridgePath = thisProcess.nowExecutingPath.dirname +/+ "WorldStateBridge.scd";
var expected = (brightness: 0.101, warmth: 0.202, abstraction: 0.303, motion: 0.404, tension: 0.505);
var sawExpected = ();
var allNormalized = true;

thisProcess.openUDPPort(6010);
OSCdef(\verify_tidal_ctrl, { |message|
    var name = message[1].asString.asSymbol;
    var value = message[2].asFloat;
    if(expected.includesKey(name)) {
        if(value.inclusivelyBetween(0, 1).not) { allNormalized = false };
        if((value - expected[name]).abs < 0.0001) { sawExpected[name] = true };
    };
}, "/ctrl", recvPort: 6010);

bridgePath.load;

Routine({
    {
        var swiftSide = NetAddr("127.0.0.1", NetAddr.langPort);

        expected.keysValuesDo { |name, value| swiftSide.sendMsg("/" ++ name, value) };
        0.2.wait;

        expected.keysValuesDo { |name, value|
            if(sawExpected[name] != true) { Error("Tidal /ctrl was not forwarded for " ++ name).throw };
        };
        if(allNormalized.not) { Error("A forwarded value escaped 0...1").throw };

        OSCdef(\verify_tidal_ctrl).free;
        "PASS: sclang received five WorldState OSC floats and forwarded Tidal /ctrl messages".postln;
        0.exit;
    }.try({ |error|
        error.reportError;
        1.exit;
    });
}).play(AppClock);
)

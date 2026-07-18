// Headless, non-audio verification for WorldStateBridge.scd. It opens Tidal's
// default control port locally and confirms the real sclang forwarding path.
(
var bridgePath = thisProcess.nowExecutingPath.dirname +/+ "WorldStateBridge.scd";
var expected = (brightness: 0.101, warmth: 0.202, abstraction: 0.303, motion: 0.404, tension: 0.505);
var sawExpected = ();
var allNormalized = true;
var sawLowClamp = false;
var sawHighClamp = false;
var sawInvalidForward = false;

if(thisProcess.openUDPPort(6010).not) {
    "ERROR: cannot bind UDP 6010; stop Tidal's controller listener before running this verification".postln;
    1.exit;
};
OSCdef(\verify_tidal_ctrl, { |message|
    var name = message[1].asString.asSymbol;
    var rawValue = message[2];
    var value;
    if(rawValue.isNumber) {
        value = rawValue.asFloat;
        if(value.inclusivelyBetween(0, 1).not) { allNormalized = false };
        if(expected.includesKey(name) and: { (value - expected[name]).abs < 0.0001 }) {
            sawExpected[name] = true;
        };
        if(name == \brightness and: { value.abs < 0.0001 }) { sawLowClamp = true };
        if(name == \tension and: { (value - 1).abs < 0.0001 }) { sawHighClamp = true };
    } {
        if(name == \brightness) { sawInvalidForward = true };
    };
}, "/ctrl", recvPort: 6010);

bridgePath.load;

Routine({
    {
        var swiftSide = NetAddr("127.0.0.1", NetAddr.langPort);

        expected.keysValuesDo { |name, value| swiftSide.sendMsg("/" ++ name, value) };
        swiftSide.sendMsg("/brightness", -0.5);
        swiftSide.sendMsg("/tension", 1.5);
        swiftSide.sendMsg("/brightness", "invalid");
        0.2.wait;

        expected.keysValuesDo { |name, value|
            if(sawExpected[name] != true) { Error("Tidal /ctrl was not forwarded for " ++ name).throw };
        };
        if(allNormalized.not) { Error("A forwarded value escaped 0...1").throw };
        if(sawLowClamp.not) { Error("brightness -0.5 was not clamped to 0.0").throw };
        if(sawHighClamp.not) { Error("tension 1.5 was not clamped to 1.0").throw };
        if(sawInvalidForward) { Error("non-numeric brightness was forwarded").throw };

        OSCdef(\verify_tidal_ctrl).free;
        "PASS: five controls forwarded, out-of-range values clamped, non-numeric value rejected".postln;
        0.exit;
    }.try({ |error|
        error.reportError;
        1.exit;
    });
}).play(AppClock);
)

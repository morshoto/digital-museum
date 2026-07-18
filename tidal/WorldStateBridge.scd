// Swift sends normalized floats to the sclang language port (57120 by
// default). Tidal's native controller input listens on 127.0.0.1:6010 for
// `/ctrl <name> <value>`, so this bridge only validates, clips, and forwards.
// It creates no synth and never stops or replaces a Tidal pattern.
(
~worldState = (
    brightness: 0.5,
    warmth: 0.5,
    abstraction: 0.3,
    motion: 0.4,
    tension: 0.2
);
~tidalWorldStateHost = "127.0.0.1";
~tidalWorldStatePort = ("EVOLVING_TIDAL_CONTROL_PORT".getenv ? "6010").asInteger;
~tidalWorldStateTarget = NetAddr(~tidalWorldStateHost, ~tidalWorldStatePort);

[\brightness, \warmth, \abstraction, \motion, \tension].do { |name|
    var definitionName = ("evolving_" ++ name).asSymbol;
    OSCdef(definitionName).free;
    OSCdef(definitionName, { |message|
        var rawValue = message[1];
        if(rawValue.isNumber) {
            var value = rawValue.asFloat.clip(0, 1);
            ~worldState[name] = value;
            ~tidalWorldStateTarget.sendMsg("/ctrl", name.asString, value);
            ("WorldState " ++ name ++ " = " ++ value.round(0.001) ++ " -> Tidal /ctrl").postln;
        } {
            ("WorldState ignored non-numeric " ++ name ++ ": " ++ rawValue).warn;
        };
    }, "/" ++ name);
};

("WorldStateBridge ready: forwarding five controls to Tidal on " ++ ~tidalWorldStateHost ++ ":" ++ ~tidalWorldStatePort).postln;
)

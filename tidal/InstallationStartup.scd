// Headless exhibition startup: boot the audio server, start SuperDirt, then
// load the transport-only WorldState bridge. Readiness markers are consumed by
// scripts/start-installation.sh; they do not claim speaker audibility.
(
var dirtPort = ("EVOLVING_DIRT_PORT".getenv ? "57120").asInteger;
var bridgePath = thisProcess.nowExecutingPath.dirname +/+ "WorldStateBridge.scd";

s.waitForBoot {
    {
        ~dirt = SuperDirt(2, s);
        ~dirt.loadSoundFiles;
        s.sync;
        ~dirt.start(dirtPort, [0, 0]);
        SuperDirt.default = ~dirt;
        bridgePath.load;
        ("INSTALLATION_SUPERDIRT_READY port=" ++ dirtPort).postln;
    }.try({ |error|
        error.reportError;
        "INSTALLATION_SUPERDIRT_FAILED".postln;
        1.exit;
    });
};
s.boot;
)

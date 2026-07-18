// Headless exhibition startup: boot the audio server, start SuperDirt, then
// load the transport-only WorldState bridge. Readiness markers are consumed by
// scripts/start-installation.sh; they do not claim speaker audibility.
(
var dirtPort = ("EVOLVING_DIRT_PORT".getenv ? "57120").asInteger;
var bridgePath = thisProcess.nowExecutingPath.dirname +/+ "WorldStateBridge.scd";
var heartbeatPath = "EVOLVING_AUDIO_HEARTBEAT_FILE".getenv;

s.waitForBoot {
    {
        ~dirt = SuperDirt(2, s);
        ~dirt.loadSoundFiles;
        s.sync;
        ~dirt.start(dirtPort, [0, 0]);
        SuperDirt.default = ~dirt;
        ~installationDirtPlayCount = 0;
        ~installationDirtHeartbeatLastWrite = 0.0;
        OSCdef(\evolving_dirt_activity).free;
        OSCdef(\evolving_dirt_activity, { |message|
            var now = Main.elapsedTime;
            var heartbeat;
            ~installationDirtPlayCount = ~installationDirtPlayCount + 1;
            if(
                heartbeatPath.notNil and:
                { (now - ~installationDirtHeartbeatLastWrite) >= 1.0 }
            ) {
                heartbeat = File(heartbeatPath, "w");
                if(heartbeat.isOpen) {
                    heartbeat.write("dirt_play_count=" ++ ~installationDirtPlayCount ++ "\n");
                    heartbeat.close;
                    ~installationDirtHeartbeatLastWrite = now;
                };
            };
        }, "/dirt/play");
        bridgePath.load;
        ("INSTALLATION_SUPERDIRT_READY port=" ++ dirtPort).postln;
    }.try({ |error|
        error.reportError;
        "INSTALLATION_SUPERDIRT_FAILED".postln;
        s.quit;
        1.exit;
    });
};
s.boot;
)

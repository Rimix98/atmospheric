// ============================================================
// Radar.qml — reader of RainViewer radar state from the Rust daemon.
//
// Everything heavy (network to RainViewer, frame choice, PNG tile decode,
// alpha pixel of the point) lives in radar-backend/ in Rust and emits a ready
// JSON string to a unix socket. QML only parses here — no Canvas and no
// rendering, so it also works inside Scope (where Quickshell has no window
// and onPaint would never fire).
//
// Daemon contract (one JSON string per message):
//   { "precip": bool, "intensity": 0..1, "fresh": bool,
//     "frame_ms": u64, "age_minutes": i64, "error": "" }
//
// Everything is fail-open: daemon not running or socket dead — lastError filled,
// fresh=false, and Weather falls back to the forecast, as before.
//
// Quickshell 0.3 API (checked against qmltypes): Socket has no onConnected/
// onDisconnected/onRead — there are connected/path, signal connectionStateChanged,
// signal error(...); data arrives via parser (SplitParser → onRead).
// ============================================================
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    property var cfg: null

    // ---------- what Weather knows (names kept) ----------
    property bool  fresh: false        // frame decoded and not older than radarMaxAgeMinutes
    property bool  precip: false       // precipitation at the point right now
    property real  gray: 0.5           // 0..1 — intensity from the gray pixel level
    property real  decodedMs: 0        // epoch (ms) of the decoded frame
    property int   ageMinutes: 0
    property string lastError: ""

    readonly property string socketPath: Quickshell.env("ATMOSPHERIC_RADAR_SOCK")
        || "/tmp/atmospheric-radar.sock"

    // The socket lives only while the Loader holds its item.
    readonly property bool daemonUp: socketLoader.item !== null && socketLoader.item.connected
    property int failTicks: 0

    // ---------- connecting to the daemon ----------
    // QLocalSocket doesn't retry a failed first connect, so on disconnect
    // the socket is recreated wholesale (see the watchdog below).
    Loader {
        id: socketLoader
        active: true
        sourceComponent: Socket {
            path: root.socketPath
            connected: true
            parser: SplitParser {
                splitMarker: "\n"
                onRead: data => root.applyJson(data)
            }
            onConnectionStateChanged: {
                if (connected) {
                    root.lastError = "";
                    root.failTicks = 0;
                } else {
                    root.fresh = false;
                    root.lastError = "daemon down";
                }
            }
            onError: err => {
                root.fresh = false;
                root.lastError = "socket err";
            }
        }
    }

    // ---------- daemon ----------
    // Lives along with QML (dies on hot-reload/stop — the watchdog spawns it),
    // so no external management is needed.
    Process {
        id: daemonProc
        command: [
            Quickshell.env("ATMOSPHERIC_RADAR_BIN")
                || Quickshell.shellPath("radar-backend/target/release/atmospheric-radar"),
            root.socketPath,
            String(root.cfg ? root.cfg.latitude : 52.9668),
            String(root.cfg ? root.cfg.longitude : 36.0625),
            String(root.cfg ? root.cfg.radarMinutes : 3),
            String(root.cfg ? root.cfg.radarMaxAgeMinutes : 25)
        ]
        // Without a parser Quickshell doesn't read the daemon's pipe: stdout/stderr
        // would clog and the daemon would hang on write. Its logs also
        // land in the quickshell journal with the [radar] prefix.
        stdout: SplitParser {
            onRead: data => { if (data.trim().length > 0) console.log("[radar] " + data); }
        }
        stderr: SplitParser {
            onRead: data => { if (data.trim().length > 0) console.warn("[radar] " + data); }
        }
        running: true
    }

    // ---------- watchdog: reconnect + respawn ----------
    Timer {
        interval: 2000
        repeat: true
        running: true
        onTriggered: {
            if (root.daemonUp) {
                root.failTicks = 0;
                return;
            }
            root.failTicks++;

            // Reconnect attempt: a fresh Socket instance
            // (QLocalSocket doesn't retry a failed first connect on its own).
            socketLoader.active = false;
            socketLoader.active = true;

            // The socket may have connected instantly — then the daemon is alive
            // and needs no touching. Check BEFORE the restart logic: otherwise the
            // failTicks reset from onConnectionStateChanged gives 0 % 10 === 0 on a
            // healthy daemon and the forced-restart branch kills it
            // every tick (this bug was looping the respawn cycle).
            if (root.daemonUp) {
                root.failTicks = 0;
                return;
            }

            root.fresh = false;
            root.lastError = "daemon down";

            // The daemon is really unreachable:
            //  - dead (running=false) — start once every 2 ticks (~4 s),
            //    to not hammer processes while the binary isn't built;
            //  - alive but not listening/answering — forced
            //    restart every 10 ticks (~20 s).
            if (!daemonProc.running && root.failTicks % 2 === 0)
                daemonProc.running = true;
            else if (daemonProc.running && root.failTicks % 10 === 0) {
                daemonProc.running = false;
                daemonProc.running = true;
            }
        }
    }

    function applyJson(line) {
        try {
            var j = JSON.parse(line);
            if (typeof j.precip === "boolean")
                root.precip = j.precip;
            if (typeof j.intensity === "number")
                root.gray = j.intensity;
            if (typeof j.fresh === "boolean")
                root.fresh = j.fresh;
            if (typeof j.frame_ms === "number")
                root.decodedMs = j.frame_ms;
            if (typeof j.age_minutes === "number")
                root.ageMinutes = j.age_minutes;
            if (typeof j.error === "string")
                root.lastError = j.error;
        } catch (e) {
            root.lastError = "radar parse: " + e;
        }
    }
}

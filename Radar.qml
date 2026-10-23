// ============================================================
// Radar.qml — читалка состояния радара RainViewer из Rust-демона.
//
// Всё тяжёлое (сеть к RainViewer, выбор кадра, декод PNG тайла, чтение
// alpha-пикселя точки) живёт в radar-backend/ на Rust и отдаёт готовый
// JSON-строку в unix-сокет. QML здесь только парсит — без Canvas и без
// рендера, поэтому работает и внутри Scope (где у Quickshell нет окна
// и onPaint никогда бы не вызвался).
//
// Контракт демона (одна JSON-строка на сообщение):
//   { "precip": bool, "intensity": 0..1, "fresh": bool,
//     "frame_ms": u64, "age_minutes": i64, "error": "" }
//
// Всё fail-open: демон не запущен или сокет мёртв — lastError заполнен,
// fresh=false, и Weather работает по прогнозу, как раньше.
//
// API Quickshell 0.3 (проверено по qmltypes): у Socket нет onConnected/
// onDisconnected/onRead — есть connected/path, signal connectionStateChanged,
// signal error(...); данные приходят через parser (SplitParser → onRead).
// ============================================================
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    property var cfg: null

    // ---------- что знает Weather (имена сохранены) ----------
    property bool  fresh: false        // кадр разобран и не старше radarMaxAgeMinutes
    property bool  precip: false       // осадки в точке прямо сейчас
    property real  gray: 0.5           // 0..1 — интенсивность по серому уровню пикселя
    property real  decodedMs: 0        // эпоха (мс) разобранного кадра
    property int   ageMinutes: 0
    property string lastError: ""

    readonly property string socketPath: Quickshell.env("ATMOSPHERIC_RADAR_SOCK")
        || "/tmp/atmospheric-radar.sock"

    // Сокет жив только пока держится item у Loader'а.
    readonly property bool daemonUp: socketLoader.item !== null && socketLoader.item.connected
    property int failTicks: 0

    // ---------- подключение к демону ----------
    // QLocalSocket не повторяет неудачную первую попытку connect, поэтому
    // при разрыве сокет пересоздаётся целиком (см. watchdog ниже).
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

    // ---------- демон ----------
    // Живёт вместе с QML (погибает при hot-reload/stop — его же поднимает
    // watchdog), поэтому снаружи управлять им не нужно.
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
        // Без парсера Quickshell не читает pipe демона: stdout/stderr
        // забились бы, и демон завис бы на записи. Заодно его логи
        // попадают в журнал quickshell с префиксом [radar].
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

            // Повторная попытка подключения: свежий экземпляр Socket
            // (QLocalSocket не повторяет неудачный первый connect сам).
            socketLoader.active = false;
            socketLoader.active = true;

            // Сокет мог подключиться сразу — тогда демон жив и трогать его
            // не нужно. Проверяем ДО логики рестартов: иначе сброс
            // failTicks от onConnectionStateChanged даёт 0 % 10 === 0 на
            // здоровом демоне и ветка принудительного перезапуска убивает
            // его каждый тик (этот баг и крутил цикл respawn'а).
            if (root.daemonUp) {
                root.failTicks = 0;
                return;
            }

            root.fresh = false;
            root.lastError = "daemon down";

            // Демон реально недоступен:
            //  - мёртв (running=false) — стартуем раз в 2 тика (~4 с),
            //    чтобы не молотить процессами, пока бинарь не собран;
            //  - жив, но не слушает/не отвечает — принудительный
            //    перезапуск раз в 10 тиков (~20 с).
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

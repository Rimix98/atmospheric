// Погодный оверлей (atmospheric) — точка входа Quickshell.
// Запуск: quickshell -p /path/to/atmospheric
//
// Scope — корневой объект: здесь живут общие для всех мониторов
// Config, Weather и IpcHandler, а Variants создаёт по окну
// на каждый экран — Wayland- или X11-вариант (см. OverlayWindow*.qml).
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    Config { id: config }

    // Один клиент погоды на весь шелл: один запрос на все мониторы.
    // id намеренно не совпадает с property weather у WeatherOverlay.
    Weather {
        id: wx
        cfg: config
    }

    // Управление снаружи: qs -p /path/to/atmospheric ipc call weather <toggle|enable|disable|refresh|test|status|state>
    IpcHandler {
        target: "weather"

        function toggle(): void { config.enabled = !config.enabled }
        function enable(): void { config.enabled = true }
        function disable(): void { config.enabled = false }
        // Для скриншотов: восстановить ровно то состояние, что было до снимка.
        function isEnabled(): string { return config.enabled ? "1" : "0" }
        function refresh(): void { wx.refresh() }

        // Эффективное состояние (то, что рисует оверлей) — одной строкой,
        // для внешних скриптов: только слово, без ветров и кодов.
        function state(): string { return wx.effectiveState }

        // Тест эффектов без перезапуска:
        //   qs -p /path/to/atmospheric ipc call weather test rain|heavy-rain|drizzle|snow|fog|fog-dense|blizzard|sleet|hail|thunder|rainbow|cloudy|night|clear|off
        function test(mode: string): string { return wx.setTest(mode) }
        function testMode(): string { return wx.testMode === "" ? "off" : wx.testMode }

        function status(): string {
            var s = wx.state;
            if (wx.provider !== "")
                s += " (" + wx.provider + ")";
            s += " code=" + wx.code;
            if (wx.loaded)
                s += " wind=" + wx.windSpeed.toFixed(1) + "m/s";
            else
                s += " (нет данных)";
            // Свежесть данных: чтобы всегда было видно, «живые» они или зависли.
            if (wx.loaded && wx.lastSuccess > 0)
                s += " upd=" + Qt.formatTime(new Date(wx.lastSuccess));
            if (config.city !== "")
                s += " city=" + config.city;
            // Модификаторы: град идёт с грозой, метель — снег с ветром,
            // «густой» — туман с видимостью меньше порога.
            if (wx.effectiveHail)
                s += " град";
            if (wx.effectiveBlizzard)
                s += " метель";
            if (wx.effectiveFogDense && wx.effectiveState === "fog")
                s += " густой";
            // Радар RainViewer: свежий кадр — осадки «прямо сейчас».
            if (wx.radarFresh) {
                let ageMin = Math.round((Date.now() - wx.radarDecodedMs) / 60000);
                s += " radar=" + (wx.radarPrecip ? "on" : "off") + "/" + ageMin + "m";
            } else {
                s += " radar=" + (wx.radarDecodedMs > 0 ? "stale" : "none")
                   + (wx.radarError !== "" ? "!" + wx.radarError : "");
            }
            if (wx.testing)
                s += " TEST[" + wx.testMode + "->" + wx.effectiveState + "]";
            if (wx.lastError !== "")
                s += " err=" + wx.lastError;
            return s;
        }
    }

    // ---------- платформа: Wayland (layer-shell) или X11 ----------
    // На Wayland окно — wlr-layer-shell, на X11 — обычный полноэкранный
    // PanelWindow с пустой маской ввода. Файлы окон разные намеренно:
    // на X11 Quickshell.Wayland не импортируется вовсе.
    readonly property bool isWayland: {
        // Приоритет у реального Qt-плагина: при QT_QPA_PLATFORM=xcb под
        // Wayland (XWayland) окно должно быть X11-шным.
        var qpa = String(Quickshell.env("QT_QPA_PLATFORM") || "").toLowerCase();
        if (qpa !== "" && qpa.indexOf(";") === -1)
            return qpa.indexOf("wayland") >= 0;
        var t = String(Quickshell.env("XDG_SESSION_TYPE") || "").toLowerCase();
        if (t !== "")
            return t === "wayland";
        return String(Quickshell.env("WAYLAND_DISPLAY") || "") !== "";
    }

    Variants {
        model: root.isWayland ? Quickshell.screens : []

        OverlayWindowWayland {
            required property var modelData
            screen: modelData
            cfg: config
            weather: wx
        }
    }

    Variants {
        model: root.isWayland ? [] : Quickshell.screens

        OverlayWindowX11 {
            required property var modelData
            screen: modelData
            cfg: config
            weather: wx
        }
    }
}

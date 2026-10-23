// Weather overlay (atmospheric) — Quickshell entry point.
// Launch: quickshell -p /path/to/atmospheric
//
// Scope is the root object: it holds the shared Config, Weather and
// IpcHandler for all monitors, and Variants creates one window
// per screen — Wayland or X11 variant (see OverlayWindow*.qml).
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    Config { id: config }

    // One weather client for the whole shell: one request for all monitors.
    // id intentionally differs from WeatherOverlay's weather property.
    Weather {
        id: wx
        cfg: config
    }

    // External control: qs -p /path/to/atmospheric ipc call weather <toggle|enable|disable|refresh|test|status|state>
    IpcHandler {
        target: "weather"

        function toggle(): void { config.enabled = !config.enabled }
        function enable(): void { config.enabled = true }
        function disable(): void { config.enabled = false }
        // For screenshots: restore exactly the state from before the shot.
        function isEnabled(): string { return config.enabled ? "1" : "0" }
        function refresh(): void { wx.refresh() }

        // Effective state (what the overlay draws) — one line,
        // for external scripts: just the word, no winds or codes.
        function state(): string { return wx.effectiveState }

        // Test effects without a restart:
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
                s += " (no data)";
            // Data freshness: always visible whether it's live or stuck.
            if (wx.loaded && wx.lastSuccess > 0)
                s += " upd=" + Qt.formatTime(new Date(wx.lastSuccess));
            if (config.city !== "")
                s += " city=" + config.city;
            // Modifiers: hail goes with thunder, blizzard is snow with wind,
            // "dense" is fog below the visibility threshold.
            if (wx.effectiveHail)
                s += " hail";
            if (wx.effectiveBlizzard)
                s += " blizzard";
            if (wx.effectiveFogDense && wx.effectiveState === "fog")
                s += " dense";
            // RainViewer radar: a fresh frame means precipitation "right now".
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

    // ---------- platform: Wayland (layer-shell) or X11 ----------
    // On Wayland the window is wlr-layer-shell; on X11 it's a regular fullscreen
    // PanelWindow with an empty input mask. The window files differ on purpose:
    // on X11 Quickshell.Wayland is not imported at all.
    readonly property bool isWayland: {
        // The real Qt plugin wins: with QT_QPA_PLATFORM=xcb under
        // Wayland (XWayland) the window must be the X11 one.
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

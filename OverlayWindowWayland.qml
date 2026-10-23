// Overlay window for Wayland: wlr-layer-shell.
// Works on Hyprland, Sway, niri, river, Wayfire, labwc, KDE Plasma
// (all compositors with zwlr-layer-shell-v1 support).
//
// A separate file is needed so X11 doesn't import Quickshell.Wayland:
// there the module is either useless or missing entirely (build without Wayland).
import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: root

    property var cfg: null
    property var weather: null

    // Full screen area: all four anchors.
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    // Transparent background (important: set before showing the window,
    // otherwise the surface stays opaque).
    color: "transparent"

    // The overlay doesn't reserve space for itself.
    exclusionMode: ExclusionMode.Ignore

    // Empty region mask: clicks pass through.
    mask: Region {}

    // Top: fullscreen windows (video, games) cover the overlay.
    // "overlay" in Config.layer: always visible on top of everything.
    WlrLayershell.layer: cfg && cfg.layer === "overlay" ? WlrLayer.Overlay : WlrLayer.Top
    WlrLayershell.namespace: "quickshell-weather"

    // When there is no effect (clear) — the window isn't shown at all,
    // instead of running an empty scene.
    visible: cfg && cfg.enabled && (weather ? (weather.active || cfg.debugSquare) : false)

    WeatherOverlay {
        anchors.fill: parent
        cfg: root.cfg
        weather: root.weather
    }
}

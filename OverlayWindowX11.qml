// Overlay window for X11: i3, bspwm, Openbox, awesome, XFCE, KDE/GNOME X11
// and any other X11 WM/DE (Quickshell built with the X11 backend).
//
// X11 specifics:
//  - no layers (layer-shell); "above normal windows" = aboveWindows
//    (WindowStaysOnTopHint), focusable: false — the window takes no focus;
//  - empty mask = clicks pass through (WindowTransparentForInput);
//  - transparency needs a compositor enabled: DEs have one built in,
//    bare WMs need picom/compton.
import QtQuick
import Quickshell

PanelWindow {
    id: root

    property var cfg: null
    property var weather: null

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}

    // No layers — just above normal windows, without focus.
    // Config.layer does nothing on X11 (there are no layers).
    aboveWindows: true
    focusable: false

    visible: cfg && cfg.enabled && (weather ? (weather.active || cfg.debugSquare) : false)

    WeatherOverlay {
        anchors.fill: parent
        cfg: root.cfg
        weather: root.weather
    }
}

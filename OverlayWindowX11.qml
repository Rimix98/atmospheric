// Окно оверлея для X11: i3, bspwm, Openbox, awesome, XFCE, KDE/GNOME X11
// и любые другие X11 WM/DE (Quickshell собирается с X11-бэкендом).
//
// Особенности X11:
//  - слоёв (layer-shell) нет; «над обычными окнами» = aboveWindows
//    (WindowStaysOnTopHint), focusable: false — окно не забирает фокус;
//  - пустая mask = клики проходят насквозь (WindowTransparentForInput);
//  - прозрачность требует включённого композитора: в DE он уже есть,
//    в голых WM нужен picom/compton.
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

    // Слоя нет — просто поверх обычных окон, без фокуса.
    // Config.layer на X11 не действует (слоёв не существует).
    aboveWindows: true
    focusable: false

    visible: cfg && cfg.enabled && (weather ? (weather.active || cfg.debugSquare) : false)

    WeatherOverlay {
        anchors.fill: parent
        cfg: root.cfg
        weather: root.weather
    }
}

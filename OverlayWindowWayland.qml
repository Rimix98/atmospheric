// Окно оверлея для Wayland: wlr-layer-shell.
// Работает на Hyprland, Sway, niri, river, Wayfire, labwc, KDE Plasma
// (все композиторы с поддержкой zwlr-layer-shell-v1).
//
// Отдельный файл нужен, чтобы на X11 не импортировался Quickshell.Wayland:
// там этот модуль либо бесполезен, либо вовсе отсутствует (сборка без Wayland).
import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: root

    property var cfg: null
    property var weather: null

    // На всю площадь экрана: все четыре якоря.
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    // Прозрачный фон (важно: задаётся до показа окна,
    // иначе поверхность останется непрозрачной).
    color: "transparent"

    // Оверлей не резервирует место под собой.
    exclusionMode: ExclusionMode.Ignore

    // Пустая регион-маска: клики проходят насквозь.
    mask: Region {}

    // Top — полноэкранные окна (видео, игры) перекрывают оверлей.
    // "overlay" в Config.layer — виден всегда поверх всего.
    WlrLayershell.layer: cfg && cfg.layer === "overlay" ? WlrLayer.Overlay : WlrLayer.Top
    WlrLayershell.namespace: "quickshell-weather"

    // Когда эффекта нет (ясно) — окно вообще не показывается,
    // а не крутит пустую сцену.
    visible: cfg && cfg.enabled && (weather ? (weather.active || cfg.debugSquare) : false)

    WeatherOverlay {
        anchors.fill: parent
        cfg: root.cfg
        weather: root.weather
    }
}

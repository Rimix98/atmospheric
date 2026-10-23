// Гроза: редкая короткая вспышка со случайным интервалом.
// Дождь при грозе рисует отдельный Rain в WeatherOverlay.
import QtQuick

Rectangle {
    id: flash

    property real peak: 0.2    // пиковая прозрачность вспышки

    anchors.fill: parent
    color: "#e8f0ff"
    opacity: 0

    function strike(): void {
        strikeAnim.restart()
    }

    SequentialAnimation {
        id: strikeAnim

        NumberAnimation {
            target: flash
            property: "opacity"
            to: flash.peak
            duration: 55
            easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: flash
            property: "opacity"
            to: flash.peak * 0.15
            duration: 90
        }
        NumberAnimation {
            target: flash
            property: "opacity"
            to: flash.peak * 0.7
            duration: 45
        }
        NumberAnimation {
            target: flash
            property: "opacity"
            to: 0
            duration: 450
            easing.type: Easing.InQuad
        }
    }

    Timer {
        id: strikeTimer

        running: flash.visible
        repeat: false
        interval: 5000 + Math.random() * 11000

        onTriggered: {
            flash.strike()
            // новый случайный интервал на этот раз
            strikeTimer.interval = 5000 + Math.random() * 11000
            strikeTimer.restart()
        }
    }
}

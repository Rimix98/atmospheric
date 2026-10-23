// Дождь: тонкие вытянутые капли, падающие под углом к ветру.
// Наклон задаётся одинаково для направления скорости (AngleDirection)
// и поворота спрайта (ImageParticle.rotation) — капель летит «вдоль» своей оси.
import QtQuick
import QtQuick.Particles

Item {
    id: root

    property real rate: 150        // частиц в секунду
    property real intensity: 1     // 0..1, из кода погоды
    property real tilt: 6          // градусы наклона (влево/вправо от ветра)
    property real speed: 950       // px/сек
    property real length: 24       // длина капли, px
    property color tint: "#7fa9e6" // цвет капель: синеватый, не белый
    property real opacityScale: 0.3 // заметность (ниже — дождь тише)

    ParticleSystem { id: ps }

    ImageParticle {
        anchors.fill: parent
        system: ps
        source: Qt.resolvedUrl("../assets/drop.svg")
        color: root.tint
        alpha: root.opacityScale
        alphaVariation: root.opacityScale * 0.6
        rotation: root.tilt
        rotationVariation: 5
        entryEffect: ImageParticle.Fade
    }

    Emitter {
        system: ps
        x: -80
        y: -24
        width: root.width + 160
        height: 1

        // частицы не плодятся, пока слой скрыт
        enabled: root.visible

        emitRate: Math.max(1, root.rate * (0.55 + 0.45 * root.intensity))
        lifeSpan: Math.round((root.height + 80) / Math.max(1, root.speed) * 1000) + 300
        lifeSpanVariation: 250
        size: root.length
        sizeVariation: Math.max(2, root.length * 0.3)

        // 90° = строго вниз; tilt > 0 — уносит вправо.
        velocity: AngleDirection {
            angle: 90 - root.tilt
            angleVariation: 4
            magnitude: root.speed
            magnitudeVariation: root.speed * 0.2
        }
    }
}

// Снег: нарисованные снежинки (assets/flake.svg) с медленным вращением.
// Два слоя глубины: дальний план — мелкие и чаще, ближний — крупные и медленные.
import QtQuick
import QtQuick.Particles

Item {
    id: root

    property real rate: 18          // частиц в секунду суммарно
    property real windX: 0          // горизонтальный разгон от ветра, px/с²
    property real speed: 75         // базовая скорость падения, px/сек
    property color tint: "#e8f1ff"
    property real opacityScale: 0.42
    property real flakeSize: 11     // базовый размер хлопья, px
    property bool blizzard: false   // метель: плотнее, косее и быстрее (снег + сильный ветер)

    readonly property real effRate:    root.rate    * (root.blizzard ? 2.2 : 1)
    readonly property real effSpeed:   root.speed   * (root.blizzard ? 1.7 : 1)
    readonly property real effWindX:   root.windX   * (root.blizzard ? 2.5 : 1)
    readonly property real effOpacity: Math.min(0.85, root.opacityScale * (root.blizzard ? 1.2 : 1))
    readonly property real effAngleVar:  root.blizzard ? 12 : 40   // метель: полосы почти параллельны
    readonly property real effAngleVar2: root.blizzard ? 16 : 30
    readonly property real effAccVar:    root.blizzard ? 8  : 20
    readonly property real effAccVar2:   root.blizzard ? 10 : 25

    ParticleSystem { id: ps }

    ImageParticle {
        anchors.fill: parent
        system: ps
        source: Qt.resolvedUrl("../assets/flake.svg")
        color: root.tint
        alpha: root.effOpacity
        alphaVariation: root.effOpacity * 0.7
        rotationVariation: 180          // случайный стартовый разворот
        rotationVelocity: 14            // медленное вращение — снежинка «играет»
        rotationVelocityVariation: 22
        entryEffect: ImageParticle.Fade
    }

    // дальний план: мелкие, быстрее, их больше
    Emitter {
        system: ps
        x: -60
        y: -30
        width: root.width + 120
        height: 1

        enabled: root.visible

        emitRate: Math.max(1, root.effRate * 0.75)
        lifeSpan: Math.round((root.height + 80) / Math.max(1, root.effSpeed * 1.4) * 1000) + 2000
        lifeSpanVariation: 3000
        size: root.flakeSize * 0.6
        sizeVariation: 2.5

        velocity: AngleDirection {
            angle: 90
            angleVariation: root.effAngleVar  // сильный дрейф, как у мелкой крупы
            magnitude: root.effSpeed * 1.4
            magnitudeVariation: 40
        }
        acceleration: AngleDirection {
            angle: root.windX >= 0 ? 0 : 180
            angleVariation: root.effAccVar
            magnitude: Math.abs(root.effWindX) * 1.4
        }
    }

    // ближний план: крупные медленные снежинки поверх
    Emitter {
        system: ps
        x: -60
        y: -30
        width: root.width + 120
        height: 1

        enabled: root.visible

        emitRate: Math.max(1, root.effRate * 0.25)
        lifeSpan: Math.round((root.height + 80) / Math.max(1, root.effSpeed * 0.7) * 1000) + 3000
        lifeSpanVariation: 4000
        size: root.flakeSize
        sizeVariation: root.flakeSize * 0.4

        velocity: AngleDirection {
            angle: 90
            angleVariation: root.effAngleVar2
            magnitude: root.effSpeed * 0.7
            magnitudeVariation: 25
        }
        acceleration: AngleDirection {
            angle: root.windX >= 0 ? 0 : 180
            angleVariation: root.effAccVar2
            magnitude: Math.abs(root.effWindX)
        }
    }
}

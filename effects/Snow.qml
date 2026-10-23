// Snow: drawn flakes (assets/flake.svg) with slow rotation.
// Two depth layers: far — small and frequent, near — large and slow.
import QtQuick
import QtQuick.Particles

Item {
    id: root

    property real rate: 18          // total particles per second
    property real windX: 0          // horizontal wind push, px/s²
    property real speed: 75         // base fall speed, px/second
    property color tint: "#e8f1ff"
    property real opacityScale: 0.42
    property real flakeSize: 11     // base flake size, px
    property bool blizzard: false   // blizzard: denser, more slanted, faster (snow + strong wind)

    readonly property real effRate:    root.rate    * (root.blizzard ? 2.2 : 1)
    readonly property real effSpeed:   root.speed   * (root.blizzard ? 1.7 : 1)
    readonly property real effWindX:   root.windX   * (root.blizzard ? 2.5 : 1)
    readonly property real effOpacity: Math.min(0.85, root.opacityScale * (root.blizzard ? 1.2 : 1))
    readonly property real effAngleVar:  root.blizzard ? 12 : 40   // blizzard: streaks nearly parallel
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
        rotationVariation: 180          // random starting rotation
        rotationVelocity: 14            // slow rotation — the flake “plays”
        rotationVelocityVariation: 22
        entryEffect: ImageParticle.Fade
    }

    // far layer: small, faster, more of them
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
            angleVariation: root.effAngleVar  // strong drift, like fine sleet
            magnitude: root.effSpeed * 1.4
            magnitudeVariation: 40
        }
        acceleration: AngleDirection {
            angle: root.windX >= 0 ? 0 : 180
            angleVariation: root.effAccVar
            magnitude: Math.abs(root.effWindX) * 1.4
        }
    }

    // near layer: large slow flakes on top
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

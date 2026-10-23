// Rain: thin elongated drops falling at an angle to the wind.
// The tilt is applied identically to the velocity direction (AngleDirection)
// and the sprite rotation (ImageParticle.rotation) — a drop flies "along" its axis.
import QtQuick
import QtQuick.Particles

Item {
    id: root

    property real rate: 150        // particles per second
    property real intensity: 1     // 0..1, from the weather code
    property real tilt: 6          // tilt degrees (left/right of the wind)
    property real speed: 950       // px/second
    property real length: 24       // drop length, px
    property color tint: "#7fa9e6" // drop color: bluish, not white
    property real opacityScale: 0.3 // visibility (lower — subtler rain)

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

        // particles don't breed while the layer is hidden
        enabled: root.visible

        emitRate: Math.max(1, root.rate * (0.55 + 0.45 * root.intensity))
        lifeSpan: Math.round((root.height + 80) / Math.max(1, root.speed) * 1000) + 300
        lifeSpanVariation: 250
        size: root.length
        sizeVariation: Math.max(2, root.length * 0.3)

        // 90° = straight down; tilt > 0 drifts right.
        velocity: AngleDirection {
            angle: 90 - root.tilt
            angleVariation: 4
            magnitude: root.speed
            magnitudeVariation: root.speed * 0.2
        }
    }
}

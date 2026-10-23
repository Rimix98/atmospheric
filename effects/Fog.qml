// Fog: small clouds drifting very slowly across the screen.
// The sprite is assets/cloud.svg (soft “puffs” blended with a radial gradient).
// Two depth layers: far (smaller, slightly faster) and near (larger,
// slower). At startup the layers' Emitter.burst() fills the screen instantly,
// after that clouds appear rarely (emitRate ≈ 0.02/s) and live long.
import QtQuick
import QtQuick.Particles

Item {
    id: root

    property real density: 1        // cloud count multiplier
    property real speed: 12         // base drift speed, px/s
    property real opacityScale: 0.45
    property color tint: "#ccd9ea"
    property real windX: 0          // wind: speed add-on (|windX| px/s)

    readonly property real drift: Math.max(1, root.speed + Math.abs(root.windX))

    ParticleSystem { id: ps }

    ImageParticle {
        anchors.fill: parent
        system: ps
        source: Qt.resolvedUrl("../assets/cloud.svg")
        color: root.tint
        alpha: root.opacityScale
        alphaVariation: root.opacityScale * 0.5
        rotationVariation: 12
        entryEffect: ImageParticle.Fade
    }

    // Initial fill: without burst we'd have to wait for the rare
    // appearances to build up the population (minutes).
    function fill() {
        far.burst(Math.max(1, Math.round(root.density * 4)))
        near.burst(Math.max(1, Math.round(root.density * 2)))
    }
    onVisibleChanged: if (visible) Qt.callLater(fill)
    Component.onCompleted: if (visible) Qt.callLater(fill)

    // far layer: smaller and slightly faster
    Emitter {
        id: far
        system: ps
        x: -260
        y: -120
        width: root.width + 260
        height: root.height + 240

        // particles don't breed while the layer is hidden
        enabled: root.visible
        emitRate: root.density * 0.022          // ≈ 4 clouds at once
        lifeSpan: Math.round((root.width + 900) / (root.drift * 1.3) * 1000) + 15000
        lifeSpanVariation: 20000
        size: 150
        sizeVariation: 80

        velocity: AngleDirection {
            angle: 0                             // strictly rightward
            angleVariation: 6
            magnitude: root.drift * 1.3
            magnitudeVariation: 4
        }
    }

    // near layer: larger and slower
    Emitter {
        id: near
        system: ps
        x: -260
        y: -120
        width: root.width + 260
        height: root.height + 240

        enabled: root.visible
        emitRate: root.density * 0.009          // ≈ 2–3 clouds at once
        lifeSpan: Math.round((root.width + 900) / (root.drift * 0.8) * 1000) + 15000
        lifeSpanVariation: 20000
        size: 260
        sizeVariation: 120

        velocity: AngleDirection {
            angle: 0
            angleVariation: 4
            magnitude: root.drift * 0.8
            magnitudeVariation: 3
        }
    }
}

// Туман: небольшие облака, очень медленно дрейфующие поперёк экрана.
// Спрайт — assets/cloud.svg (слияние мягких «пуфов» с радиальным градиентом).
// Два слоя глубины: дальний план (мельче, чуть быстрее) и ближний (крупнее,
// медленнее). На старте слоя Emitter.burst() мгновенно заполняет экран,
// дальше облака появляются редко (emitRate ≈ 0.02/с) и живут долго.
import QtQuick
import QtQuick.Particles

Item {
    id: root

    property real density: 1        // множитель количества облаков
    property real speed: 12         // базовая скорость дрейфа, px/с
    property real opacityScale: 0.45
    property color tint: "#ccd9ea"
    property real windX: 0          // ветер: добавка к скорости (|windX| px/с)

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

    // Первое заполнение: без burst пришлось бы ждать, пока редкие
    // появления нарастят популяцию (минуты).
    function fill() {
        far.burst(Math.max(1, Math.round(root.density * 4)))
        near.burst(Math.max(1, Math.round(root.density * 2)))
    }
    onVisibleChanged: if (visible) Qt.callLater(fill)
    Component.onCompleted: if (visible) Qt.callLater(fill)

    // дальний план: мельче и чуть быстрее
    Emitter {
        id: far
        system: ps
        x: -260
        y: -120
        width: root.width + 260
        height: root.height + 240

        // частицы не плодятся, пока слой скрыт
        enabled: root.visible
        emitRate: root.density * 0.022          // ≈ 4 облака одновременно
        lifeSpan: Math.round((root.width + 900) / (root.drift * 1.3) * 1000) + 15000
        lifeSpanVariation: 20000
        size: 150
        sizeVariation: 80

        velocity: AngleDirection {
            angle: 0                             // строго вправо
            angleVariation: 6
            magnitude: root.drift * 1.3
            magnitudeVariation: 4
        }
    }

    // ближний план: крупнее и медленнее
    Emitter {
        id: near
        system: ps
        x: -260
        y: -120
        width: root.width + 260
        height: root.height + 240

        enabled: root.visible
        emitRate: root.density * 0.009          // ≈ 2–3 облака одновременно
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

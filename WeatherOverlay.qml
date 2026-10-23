// Слой эффектов: выбирает, что рисовать по состоянию погоды.
import QtQuick
import "effects"

Item {
    id: root

    property var cfg: null
    property var weather: null

    readonly property string st: weather ? weather.effectiveState : "unknown"
    readonly property bool precip: st === "rain" || st === "heavyRain"
                                || st === "drizzle" || st === "thunder"
                                || st === "sleet"
    // густой туман / метель / град — модификаторы состояния из Weather
    readonly property bool fogDense: weather && weather.effectiveFogDense
    readonly property bool blizzard: weather && weather.effectiveBlizzard
    readonly property bool hail: weather && weather.effectiveHail

    // ---------- лёгкое затемнение при облачности ----------
    Rectangle {
        anchors.fill: parent
        color: "#101820"
        visible: root.st === "cloudy" && root.cfg && root.cfg.dimCloudy
        opacity: root.cfg ? root.cfg.cloudyDimOpacity : 0.1
    }

    // ---------- дождь / морось / гроза / дождь со снегом ----------
    // Гроза (thunder) — ливень и гуще: rate выше heavyRainRate плюс вспышки.
    Rain {
        anchors.fill: parent
        visible: root.precip
        rate: root.st === "drizzle" ? root.cfg.drizzleRate
            : (root.st === "heavyRain" ? root.cfg.heavyRainRate
            : (root.st === "thunder" ? root.cfg.thunderRate
            : (root.st === "sleet" ? root.cfg.sleetRainRate
                                   : root.cfg.rainRate)))
        speed: root.st === "drizzle" ? 600
            : (root.st === "heavyRain" ? 1350
            : (root.st === "thunder" ? 1500
            : (root.st === "sleet" ? 850 : 950)))
        length: (root.st === "drizzle" || root.st === "sleet")
                ? root.cfg.rainLength * 0.7
                : root.cfg.rainLength
        tint: root.cfg.rainColor
        opacityScale: root.cfg.rainOpacity
        intensity: root.weather ? root.weather.effectiveIntensity : 0.8
        tilt: root.weather ? root.weather.effectiveTilt : 0
    }

    // ---------- град: короткие быстрые крупинки поверх грозы (WMO 96/99) ----------
    Rain {
        anchors.fill: parent
        visible: root.hail
        rate: root.cfg.hailRate
        speed: 1450
        length: root.cfg.rainLength * 0.45
        tint: root.cfg.hailColor
        opacityScale: Math.min(0.6, root.cfg.rainOpacity * 1.4)
        intensity: root.weather ? root.weather.effectiveIntensity : 0.9
        tilt: root.weather ? root.weather.effectiveTilt : 0
    }

    // ---------- снег / дождь со снегом / метель ----------
    Snow {
        anchors.fill: parent
        visible: root.st === "snow" || root.st === "sleet"
        rate: root.st === "sleet" ? root.cfg.sleetSnowRate
                                  : root.cfg.snowRate
        windX: (root.weather ? root.weather.effectiveTilt : 0) * 2.5
        tint: root.cfg.snowColor
        opacityScale: root.cfg.snowOpacity
        flakeSize: root.cfg.snowSize
        blizzard: root.blizzard
    }

    // ---------- туман: небольшие облака, очень медленный дрейф ----------
    // Густой туман (видимость < fogDenseVisibilityM): облака плотнее и заметнее.
    Fog {
        anchors.fill: parent
        visible: root.st === "fog"
        density: root.cfg.fogDensity * (root.fogDense ? 1.9 : 1)
        speed: root.cfg.fogSpeed
        opacityScale: Math.min(0.9, root.cfg.fogOpacity * (root.fogDense ? 1.3 : 1))
        tint: root.cfg.fogColor
        windX: (root.weather ? root.weather.effectiveTilt : 0) * 0.15
    }

    // ---------- радуга после дождя ----------
    Rainbow {
        anchors.fill: parent
        visible: root.st === "rainbow"
        opacityScale: root.cfg.rainbowOpacity
    }

    // ---------- вспышки молний ----------
    Lightning {
        anchors.fill: parent
        visible: root.st === "thunder"
        peak: root.cfg.flashPeakOpacity
    }

    // ---------- ночь: холодный оттенок (яркость почти не трогает) ----------
    // Гашение экрана — только при включённом nightDim: именно оно «крутит»
    // яркость, поэтому по умолчанию спит.
    Rectangle {
        anchors.fill: parent
        color: "#0a1a3a"
        visible: root.weather && root.weather.effectiveIsDay === 0
                 && root.cfg && (root.cfg.nightDim || root.cfg.nightTintOpacity > 0.001)
        opacity: !root.cfg ? 0
                 : (root.cfg.nightDim ? root.cfg.nightOpacity
                                      : root.cfg.nightTintOpacity)
    }

    // ---------- отладка (этап 1 и диагностика) ----------
    Rectangle {
        anchors.fill: parent
        visible: root.cfg && root.cfg.debugSquare
        color: "#55ff0000"
    }

    Text {
        anchors {
            left: parent.left
            bottom: parent.bottom
            margins: 16
        }
        visible: root.cfg && root.cfg.debugSquare
        color: "white"
        font.family: "monospace"
        font.pixelSize: 14
        text: root.weather
            ? ((root.weather.testing ? "TEST[" + root.weather.testMode + "]  " : "")
               + "state=" + root.weather.effectiveState
               + "  src=" + root.weather.provider
               + "  code=" + root.weather.code
               + "  intensity=" + root.weather.effectiveIntensity.toFixed(2)
               + "  wind=" + root.weather.windSpeed.toFixed(1) + "m/s dir=" + root.weather.windDirection
               + "  is_day=" + root.weather.effectiveIsDay
               + "  tilt=" + root.weather.effectiveTilt.toFixed(1) + "°"
               + "  vis=" + (root.weather.visibilityM >= 0
                             ? Math.round(root.weather.visibilityM) + "m" : "—")
               + (root.hail ? "  HAIL" : "")
               + (root.blizzard ? "  BLIZZARD" : "")
               + (root.fogDense ? "  DENSE" : "")
               + (root.weather.lastError !== "" ? "  err=" + root.weather.lastError : ""))
            : ""
    }
}

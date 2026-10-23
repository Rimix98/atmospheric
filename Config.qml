// All overlay settings in one place.
import QtQuick

QtObject {
    // ---------- City and API ----------
    property string city: "New York"
    property real latitude: 40.7128
    property real longitude: -74.0060
    property int refreshMinutes: 10      // Open-Meteo/Yr poll interval (plus 0..2 min of jitter)
    property int radarMinutes: 3         // RainViewer frame list poll (one frame every 10 min)
    property int radarMaxAgeMinutes: 25  // radar frame freshness; older — fall back to the forecast

    // ---------- Behavior ----------
    property bool enabled: true          // master switch (atmospheric toggle)
    property string layer: "top"         // "top" — under fullscreen windows,
                                         // "overlay" — always on top of everything
    property bool debugSquare: false     // stage 1: translucent red square + debug text

    // ---------- Cloud cover ----------
    property bool dimCloudy: false       // dimming for cloud cover (codes 2-3) —
                                          // REMOVED by request: cloud cover draws
                                          // nothing anymore, window hidden in daytime
    property real cloudyDimOpacity: 0.10 // in case you want to bring it back

    // ---------- Night ----------
    property bool nightDim: false        // DIM the screen at night (really changes brightness!)
                                          // — off by default
    property real nightOpacity: 0.18     // dim strength when nightDim: true
    property real nightTintOpacity: 0.06 // cool tint at night — barely touches brightness

    // ---------- Thunderstorm ----------
    property real flashPeakOpacity: 0.20 // peak flash opacity

    // ---------- Fog ----------
    property real fogDensity: 2.5        // cloud count multiplier (2.5 ≈ 2.5× denser)
    property color fogColor: "#ccd9ea"    // grayish blue: readable on both white and dark
    property real fogSpeed: 12           // cloud drift, px/s (12 ≈ 2.5 min per crossing)
    property real fogOpacity: 0.45       // fog visibility (0..1)
    // Second fog signal: visibility from Open-Meteo (hourly bin).
    // WMO 45/48 stays primary; visibility catches "haze" without a fog code.
    property real fogVisibilityM: 1000   // below this visibility — fog
    property real fogDenseVisibilityM: 300 // below — dense fog (clouds denser and more visible)

    // ---------- Blizzard ----------
    property real blizzardWind: 8        // snow + stronger wind — blizzard: denser, more slanted, faster

    // ---------- Sleet (freezing rain, WMO 66/67) ----------
    property int sleetRainRate: 90       // the rain part of the mix
    property int sleetSnowRate: 12       // the snow part of the mix

    // ---------- Hail (only with thunder, WMO 96/99) ----------
    property color hailColor: "#e3eefb"  // grains: cool white, unlike the bluish rain
    property int hailRate: 240           // short fast grains over the rain

    // ---------- Rainbow after rain ----------
    property bool rainbowEnabled: true
    property int rainbowMinutes: 30      // how many minutes after rain the arc may appear
    property real rainbowMaxSunAlt: 42   // sun higher — the rainbow is physically invisible
    property real rainbowOpacity: 0.40   // arc visibility (0..1) — quiet, not a screensaver

    // ---------- Intensity: particles per second ----------
    // The actual number of simultaneous particles ≈ rate * lifetime (s).
    // Rain (lifetime ~1.2 s): 150 → ~180 drops on screen.
    property int drizzleRate: 60
    property int rainRate: 150
    property int heavyRainRate: 260
    property int thunderRate: 350         // thunderstorm: downpour and denser — a solid "wall"
    property int snowRate: 18            // snow lives ~16 s: 18 → ~290 flakes

    // ---------- Look of drops and flakes ----------
    property color rainColor: "#7fa9e6"   // rain: bluish, not white
    property real rainOpacity: 0.30       // drop visibility (0..1, lower — subtler)
    property real rainLength: 20          // drop length, px
    property color snowColor: "#e8f1ff"   // flakes: slightly cool white
    property real snowOpacity: 0.42       // snow visibility
    property real snowSize: 11            // base flake size, px
}

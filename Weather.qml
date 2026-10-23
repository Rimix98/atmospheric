// Weather client: a race of two providers — Open-Meteo and met.no (Yr).
// Requests run in PARALLEL; the first success wins, the loser is cancelled.
//
// Why two: from some networks the route to api.open-meteo.com (Hetzner FSN1,
// 94.130.142.35) is a black hole — both curl and XHR hang (checked: TCP timeout,
// DNS is fine). api.met.no answers in ~0.3 s, so the
// overlay works either way.
//
// If both fail the state is NOT reset — the last known one remains.
import QtQuick
import Quickshell

Item {
    id: root

    property var cfg: null

    // ---------- last known state ----------
    property int code: -1
    property string state: "unknown"     // clear|cloudy|fog|drizzle|rain|heavyRain|sleet|snow|thunder
    property real intensity: 0           // 0..1 — effect intensity multiplier
    property real windSpeed: 0           // m/s
    property int windDirection: 0        // degrees, wind origin direction (meteorological standard)
    property real temperature: 15        // °C at ground level — radar decides rain vs snow
    property int isDay: 1                // 1 — day, 0 — night
    property bool loaded: false          // whether any request ever succeeded
    property string lastError: ""
    property real lastSuccess: 0         // Date.now() of the last success
    property string provider: ""         // data source: open-meteo | yr

    property real visibilityM: -1        // visibility in meters (Open-Meteo), −1 = no data
    property double lastRainMs: 0        // time of the last "wet" state (for the rainbow)
    property int nowTick: 0              // tick once a minute — recompute time-dependent conditions

    // ---------- request race ----------
    property bool inflight: false        // a poll round is in progress
    property bool won: false             // a success already happened this round
    property int pending: 0              // how many requests haven't finished yet
    property var cancellers: []           // cancel functions for the current round

    // ---------- test modes ----------
    // Set via the ATMOSPHERIC_TEST env var (see scripts/run.sh):
    //   rain | heavy-rain | drizzle | snow | fog | thunder | cloudy | night | clear
    // or at runtime: qs -p /path/to/atmospheric ipc call weather test snow
    // Tests do NOT touch real data: the API is still polled,
    // and the effective* properties override what the overlay draws.
    property string testMode: {
        if (typeof Quickshell.env !== "function")
            return "";
        var v = Quickshell.env("ATMOSPHERIC_TEST");
        if (!v)
            return "";
        var s = String(v).toLowerCase().trim();
        return (s === "off" || s === "auto") ? "" : s;
    }

    readonly property bool testing: testMode !== ""

    function setTest(mode: string): string {
        var m = mode.toLowerCase().trim();
        var known = ["", "off", "auto", "clear", "cloudy", "fog", "fog-dense",
                     "drizzle", "rain", "heavy-rain", "heavyrain", "snow",
                     "blizzard", "sleet", "thunder", "storm", "hail",
                     "rainbow", "night"];
        if (known.indexOf(m) === -1)
            return "unknown mode '" + mode + "', use: off|clear|cloudy|fog|fog-dense|drizzle|rain|heavy-rain|snow|blizzard|sleet|thunder|hail|rainbow|night";
        testMode = (m === "off" || m === "auto") ? "" : m;
        return testMode === "" ? "test off (real weather)" : "test: " + testMode;
    }

    // State without "decorations" (rainbow for now): real data or test.
    readonly property string composedState: {
        switch (testMode) {
        case "":             return composeState(state);
        case "night":        return composeState(state);         // night is isDay, the state is still real
        case "clear":
        case "off":          return "clear";
        case "cloudy":       return "cloudy";
        case "fog":
        case "fog-dense":    return "fog";
        case "drizzle":      return "drizzle";
        case "rain":         return "rain";
        case "heavyrain":
        case "heavy-rain":   return "heavyRain";
        case "snow":         return "snow";
        case "blizzard":     return "snow";
        case "sleet":        return "sleet";
        case "hail":         return "thunder";                   // hail only comes with thunder
        case "thunder":
        case "storm":        return "thunder";
        case "rainbow":      return "rainbow";
        default:             return state;
        }
    }

    // Rainbow: rain ended recently, the sky is clear, and the sun is low
    // (the arc is only visible while alt < 42° — primary rainbow physics).
    readonly property bool rainbowNow: {
        nowTick;                                 // time is not reactive — tick once a minute
        if (testMode !== "")
            return false;                        // in test mode rainbow is set by the case above
        if (!cfg || !cfg.rainbowEnabled)
            return false;
        if (composedState !== "clear" && composedState !== "cloudy")
            return false;
        if (effectiveIsDay !== 1 || lastRainMs <= 0)
            return false;
        if (Date.now() - lastRainMs > cfg.rainbowMinutes * 60000)
            return false;
        var alt = sunAltitudeDeg(Date.now(), cfg.latitude, cfg.longitude);
        return alt > 0.5 && alt < cfg.rainbowMaxSunAlt;
    }

    // What the overlay actually draws (test beats real data).
    readonly property string effectiveState:
        (testMode === "" && rainbowNow) ? "rainbow" : composedState;

    // ---------- current state modifiers ----------
    // Hail in the WMO table only comes with thunder (codes 96/99).
    readonly property bool effectiveHail: {
        if (testMode === "hail") return true;
        return testMode === "" && (code === 96 || code === 99);
    }
    // Blizzard: snow plus wind above the threshold.
    readonly property bool effectiveBlizzard: {
        if (testMode === "blizzard") return true;
        return testMode === "" && effectiveState === "snow"
               && windSpeed >= (cfg ? cfg.blizzardWind : 8);
    }
    // Dense fog by visibility depth (codes 45/48 stay the primary signal).
    readonly property bool effectiveFogDense: {
        if (testMode === "fog-dense") return true;
        return testMode === "" && visibilityM >= 0
               && visibilityM < (cfg ? cfg.fogDenseVisibilityM : 300);
    }

    // While rain was falling — remember the moment: it's needed for the rainbow.
    onEffectiveStateChanged: {
        switch (effectiveState) {
        case "drizzle": case "sleet": case "rain":
        case "heavyRain": case "thunder":
            lastRainMs = Date.now();
            break;
        }
    }

    readonly property int effectiveIsDay: {
        if (testMode === "")     return isDay;
        if (testMode === "night") return 0;
        return 1;
    }

    readonly property real effectiveIntensity: {
        if (testMode === "") {
            // A fresh radar sees precipitation — intensity from the gray pixel
            // level (black = weak, white = strong); otherwise from the forecast.
            if (radar.fresh && radar.precip)
                return Math.min(1, 0.3 + radar.gray * 0.7);
            return intensity;
        }
        if (testMode === "drizzle")   return 0.4;
        if (testMode === "rain")      return 0.7;
        if (testMode === "heavyrain" || testMode === "heavy-rain") return 1.0;
        return 0.7;
    }

    // In a test without loaded data — a slight tilt so drops are visible.
    readonly property real effectiveTilt: (testing && !loaded) ? 8 : tilt

    // Drop tilt by wind, degrees (±25).
    // wind_direction_10m is "from": eastward motion = -sin(dir).
    readonly property real tilt: {
        var horizontal = -Math.sin(windDirection * Math.PI / 180) * windSpeed;
        return Math.max(-25, Math.min(25, horizontal * 1.2));
    }

    // ---------- RainViewer radar: a "real-time" precipitation layer ----------
    // The forecast (Yr) gives precipitation in hourly bins and "lags" reality:
    // rain has passed but the bin still pours for an hour. The radar observes every
    // 10 minutes: a fresh frame with a precip pixel turns rain/snow on, a clean
    // point kills the forecast bins. Fog/wind/cloud cover the radar can't see
    // stays from the forecast. In status: radar=on/3m | off/3m | stale | none.
    Radar {
        id: radar
        cfg: root.cfg
    }
    readonly property bool   radarFresh:     radar.fresh
    readonly property bool   radarPrecip:    radar.precip
    readonly property real   radarDecodedMs: radar.decodedMs
    readonly property string radarError:     radar.lastError

    // Merge forecast and radar into one overlay state (test mode is above).
    function composeState(base) {
        if (!radar.fresh)
            return base;
        if (radar.precip) {
            if (base === "thunder")
                return "thunder";            // forecast knows the thunder — the radar doesn't cancel it
            if (temperature <= 0.5)
                return "snow";               // cold + radar = snow
            if (base === "drizzle" || base === "rain" || base === "heavyRain" || base === "sleet")
                return base;                 // intensity — from the forecast
            return "rain";                   // precipitation started ahead of the forecast
        }
        // Radar is clear: kill forecast showers/snow/thunder/mixed precipitation.
        // Drizzle stays — the radar barely sees it, and the drops are light.
        if (base === "rain" || base === "heavyRain" || base === "snow" || base === "thunder" || base === "sleet")
            return "cloudy";
        return base;
    }

    // Whether to draw the overlay at all (in a test — always, except explicit clear/off
    // and cloudy: dimCloudy removed, cloudy shows nothing anymore).
    readonly property bool active: (loaded || testing) && (
        (effectiveState !== "clear" && effectiveState !== "cloudy")
        || effectiveIsDay === 0
        || (effectiveState === "cloudy" && cfg && cfg.dimCloudy)
    )

    // ---------- WMO mapping ----------
    function stateFor(c) {
        if (c >= 0 && c <= 3)  return c <= 1 ? "clear" : "cloudy";
        if (c === 45 || c === 48) return "fog";
        if (c >= 51 && c <= 55) return "drizzle";           // drizzle
        if (c === 56 || c === 57 || c === 66 || c === 67)
            return "sleet";                                 // freezing drizzle/rain → rain with snow
        if (c >= 61 && c <= 63) return "rain";
        if (c === 65) return "heavyRain";                   // downpour
        if (c === 80) return "rain";
        if (c >= 81 && c <= 82) return "heavyRain";         // heavy showers
        if (c >= 71 && c <= 77) return "snow";
        if (c === 85 || c === 86) return "snow";
        if (c >= 95 && c <= 99) return "thunder";           // 96/99 — with hail (see effectiveHail)
        return "cloudy";                                     // unknown code — a gentle cloud
    }

    function intensityFor(c) {
        if (c === 61 || c === 80) return 0.45;
        if (c === 63) return 0.7;
        if (c === 65) return 1.0;
        if (c === 56 || c === 66) return 0.35;              // rain with snow: light
        if (c === 57 || c === 67) return 0.9;               // rain with snow: heavy
        if (c === 81) return 0.85;
        if (c === 82) return 1.0;
        if (c >= 51 && c <= 55) return 0.3 + (c - 51) * 0.05;
        if (c === 85) return 0.6;
        if (c === 86) return 0.9;
        if (c >= 71 && c <= 77) return 0.4 + (c - 71) * 0.06;
        if (c >= 95) return 0.9;
        return 0.6;
    }

    // Yr (met.no) symbol → nearest WMO code, so the common mapping works.
    function yrToWmo(sym) {
        var s = String(sym).toLowerCase();
        if (s.indexOf("thunder") !== -1) return s.indexOf("heavy") !== -1 ? 99 : 95;
        if (s.indexOf("snow") !== -1) {
            if (s.indexOf("heavy") !== -1) return s.indexOf("shower") !== -1 ? 86 : 75;
            if (s.indexOf("light") !== -1) return s.indexOf("shower") !== -1 ? 85 : 71;
            return s.indexOf("shower") !== -1 ? 85 : 73;
        }
        if (s.indexOf("sleet") !== -1 || s.indexOf("freezing") !== -1 || s.indexOf("wintry") !== -1)
            return s.indexOf("heavy") !== -1 ? 67 : 66;     // rain with snow
        if (s.indexOf("rain") !== -1 || s.indexOf("drizzle") !== -1) {
            if (s.indexOf("heavy") !== -1) return s.indexOf("shower") !== -1 ? 81 : 65;
            if (s.indexOf("light") !== -1) return s.indexOf("shower") !== -1 ? 80 : 61;
            return s.indexOf("shower") !== -1 ? 80 : 62;
        }
        if (s.indexOf("fog") !== -1) return 45;
        if (s.indexOf("partly") !== -1) return 2;
        if (s.indexOf("cloud") !== -1 || s.indexOf("overcast") !== -1) return 3;
        if (s.indexOf("fair") !== -1) return 1;
        if (s.indexOf("clear") !== -1) return 0;
        return 3;
    }

    // Sun altitude in degrees (SunCalc algorithm).
    // Checked against api.met.no/weatherapi/sunrise for Orel (2026-10-15):
    // sunrise 07:01 = 07:01, sunset 17:41 ≈ 17:40, noon altitude ±0.2°.
    function sunAltitudeDeg(dateMs, lat, lon) {
        var rad = Math.PI / 180;
        var d = dateMs / 86400000 + 2440587.5 - 2451545.0;   // days since J2000
        var M = rad * (357.5291 + 0.98560028 * d);
        var C = rad * (1.9148 * Math.sin(M) + 0.02 * Math.sin(2 * M) + 0.0003 * Math.sin(3 * M));
        var L = M + C + rad * 102.9372 + Math.PI;
        var e = rad * 23.4397;
        var dec = Math.asin(Math.sin(e) * Math.sin(L));
        var ra = Math.atan2(Math.sin(L) * Math.cos(e), Math.cos(L));
        var H = rad * (280.16 + 360.9856235 * d) + rad * lon - ra;
        var phi = rad * lat;
        return Math.asin(Math.sin(phi) * Math.sin(dec)
                         + Math.cos(phi) * Math.cos(dec) * Math.cos(H)) / rad;
    }

    // ---------- endpoints ----------
    function omEndpoint() {
        return "https://api.open-meteo.com/v1/forecast"
            + "?latitude=" + cfg.latitude
            + "&longitude=" + cfg.longitude
            + "&current=weather_code,temperature_2m,wind_speed_10m,wind_direction_10m,is_day"
            + "&hourly=visibility"                // second fog signal (in meters, hourly)
            + "&wind_speed_unit=ms"
            + "&timezone=auto";
    }

    function yrEndpoint() {
        return "https://api.met.no/weatherapi/locationforecast/2.0/compact"
            + "?lat=" + cfg.latitude
            + "&lon=" + cfg.longitude;
    }

    // ---------- applying responses ----------
    function commit() {
        loaded = true;
        lastSuccess = Date.now();
    }

    // open-meteo: data = the full response (current + hourly)
    function applyOm(data) {
        var cur = data.current || data;
        code = cur.weather_code;
        state = stateFor(cur.weather_code);
        intensity = intensityFor(cur.weather_code);
        if (typeof cur.wind_speed_10m === "number")
            windSpeed = cur.wind_speed_10m;
        if (typeof cur.wind_direction_10m === "number")
            windDirection = cur.wind_direction_10m;
        if (typeof cur.temperature_2m === "number")
            temperature = cur.temperature_2m;
        if (typeof cur.is_day === "number")
            isDay = cur.is_day;

        // Fog by visibility — a second signal besides codes 45/48.
        // Visibility is also low in heavy rain/snow — those states have priority.
        visibilityM = -1;
        var h = data.hourly;
        if (h && h.visibility && h.time && cur.time) {
            var idx = h.time.indexOf(String(cur.time).slice(0, 13) + ":00");
            if (idx >= 0 && typeof h.visibility[idx] === "number")
                visibilityM = h.visibility[idx];
        }
        if (visibilityM >= 0 && visibilityM < cfg.fogVisibilityM
            && state !== "rain" && state !== "heavyRain"
            && state !== "snow" && state !== "thunder")
            state = "fog";
        commit();
    }

    // met.no/Yr: data = the full Feature; no WMO code — derive it from the symbol,
    // compute is_day ourselves (Yr's response lacks it).
    function applyYr(f) {
        var d0 = f.properties.timeseries[0].data || {};
        var det = (d0.instant && d0.instant.details) || {};
        var sym = "";
        if (d0.next_1_hours && d0.next_1_hours.summary)
            sym = d0.next_1_hours.summary.symbol_code || "";
        if (!sym && d0.next_6_hours && d0.next_6_hours.summary)
            sym = d0.next_6_hours.summary.symbol_code || "";

        if (sym) {
            code = yrToWmo(sym);
            state = stateFor(code);
            intensity = intensityFor(code);
        } else {
            // No symbol — cloud cover from instant.details.
            var cloud = (typeof det.cloud_area_fraction === "number") ? det.cloud_area_fraction : 0;
            state = cloud >= 50 ? "cloudy" : "clear";
            code = state === "cloudy" ? 3 : 0;
            intensity = 0.6;
        }

        if (typeof det.wind_speed === "number")
            windSpeed = det.wind_speed;
        if (typeof det.wind_from_direction === "number")
            windDirection = det.wind_from_direction;
        if (typeof det.air_temperature === "number")
            temperature = det.air_temperature;
        isDay = sunAltitudeDeg(Date.now(), cfg.latitude, cfg.longitude) > -0.833 ? 1 : 0;
        visibilityM = -1;                       // Yr provides no visibility — no fog signal
        commit();
    }

    // ---------- race ----------
    // settle accounts for exactly one outcome per request (myDone flag in the closure),
    // so aborting the loser doesn't decrement pending again.
    function settle(ok, data, err, src) {
        pending = pending - 1;
        if (ok && !won) {
            won = true;
            provider = src;
            if (src === "open-meteo")
                root.applyOm(data);
            else
                root.applyYr(data);
            lastError = "";
            cancelRound();                       // loser: myDone → no-op + abort
        } else if (!ok && !won) {
            lastError = lastError === "" ? (src + ": " + err)
                                         : (lastError + " | " + src + ": " + err);
        }
        if (pending <= 0)
            finishRound();
    }

    function cancelRound() {
        for (var i = 0; i < cancellers.length; i++)
            cancellers[i]();
    }

    function finishRound() {
        if (!inflight)
            return;                              // idempotent
        inflight = false;
        cancellers = [];
    }

    function refresh() {
        if (!cfg || inflight)
            return;
        inflight = true;
        won = false;
        pending = 2;
        cancellers = [];
        lastError = "";
        fetchOpenMeteo();
        fetchYr();
    }

    function fetchOpenMeteo() {
        var xhr = new XMLHttpRequest();
        var myDone = false;
        cancellers.push(function() {
            if (myDone)
                return;
            myDone = true;
            pending = pending - 1;
            if (pending <= 0)
                finishRound();
            try { xhr.abort(); } catch (e) {}
        });
        function finish(ok, data, err) {
            if (myDone)
                return;
            myDone = true;
            settle(ok, data, err, "open-meteo");
        }
        try {
            xhr.open("GET", omEndpoint(), true);
        } catch (e) {
            finish(false, null, String(e));
            return;
        }
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== 4)
                return;
            if (xhr.status === 200) {
                try {
                    var d = JSON.parse(xhr.responseText);
                    var cur = d.current || d;
                    if (typeof cur.weather_code !== "number")
                        finish(false, null, "bad payload");
                    else
                        finish(true, d, "");    // applyOm needs hourly.visibility too
                } catch (e) {
                    finish(false, null, "parse: " + e);
                }
            } else {
                // Network error: state untouched, the last known one remains.
                finish(false, null, xhr.status === 0 ? "network error" : "http " + xhr.status);
            }
        };
        xhr.onerror = function() { finish(false, null, "network error"); };
        xhr.send(null);
    }

    function fetchYr() {
        var xhr = new XMLHttpRequest();
        var myDone = false;
        cancellers.push(function() {
            if (myDone)
                return;
            myDone = true;
            pending = pending - 1;
            if (pending <= 0)
                finishRound();
            try { xhr.abort(); } catch (e) {}
        });
        function finish(ok, data, err) {
            if (myDone)
                return;
            myDone = true;
            settle(ok, data, err, "yr");
        }
        try {
            xhr.open("GET", yrEndpoint(), true);
            // met.no asks for a meaningful User-Agent; if Qt won't send the header —
            // the server answers anyway (checked on a live instance).
            try { xhr.setRequestHeader("User-Agent", "atmospheric-quickshell/1.0"); } catch (e) {}
        } catch (e) {
            finish(false, null, String(e));
            return;
        }
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== 4)
                return;
            if (xhr.status === 200) {
                try {
                    var f = JSON.parse(xhr.responseText);
                    if (!f.properties || !f.properties.timeseries || !f.properties.timeseries.length)
                        finish(false, null, "bad payload");
                    else
                        finish(true, f, "");
                } catch (e) {
                    finish(false, null, "parse: " + e);
                }
            } else {
                finish(false, null, xhr.status === 0 ? "network error" : "http " + xhr.status);
            }
        };
        xhr.onerror = function() { finish(false, null, "network error"); };
        xhr.send(null);
    }

    // Sun/date are not reactive in bindings — tick once a minute so
    // conditions like the rainbow get recomputed in time.
    Timer {
        interval: 60 * 1000
        repeat: true
        running: true
        onTriggered: root.nowTick++
    }

    // Main poll: every refreshMinutes, the first one immediately at start.
    // After each cycle 0..2 min of random delay is added to the interval —
    // met.no's Terms ask not to hammer traffic on a fixed schedule.
    Timer {
        property int base: Math.max(5, root.cfg ? root.cfg.refreshMinutes : 10) * 60 * 1000
        interval: base
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root.refresh()
            interval = base + Math.floor(Math.random() * 120000)
        }
    }

    // Quick retry: while not loaded or after an error — every minute.
    Timer {
        interval: 60 * 1000
        running: !root.loaded || root.lastError !== ""
        repeat: true
        onTriggered: root.refresh()
    }
}

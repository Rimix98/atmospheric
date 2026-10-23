// Клиент погоды: гонка двух провайдеров — Open-Meteo и met.no (Yr).
// Запросы идут ПАРАЛЛЕЛЬНО, побеждает первый успешный; проигравший отменяется.
//
// Зачем два: с некоторых сетей маршрут до api.open-meteo.com (Hetzner FSN1,
// 94.130.142.35) чёрная дыра — висят и curl, и XHR (проверено: TCP-таймаут,
// при этом DNS честный). api.met.no при этом отвечает за ~0.3 с, так что
// оверлей работает в любом случае.
//
// При ошибке обоих состояние НЕ сбрасывается — остаётся последнее известное.
import QtQuick
import Quickshell

Item {
    id: root

    property var cfg: null

    // ---------- последнее известное состояние ----------
    property int code: -1
    property string state: "unknown"     // clear|cloudy|fog|drizzle|rain|heavyRain|sleet|snow|thunder
    property real intensity: 0           // 0..1 — множитель интенсивности эффекта
    property real windSpeed: 0           // м/с
    property int windDirection: 0        // градусы, откуда дует (метео-стандарт)
    property real temperature: 15        // °C у земли — радар решает, дождь это или снег
    property int isDay: 1                // 1 — день, 0 — ночь
    property bool loaded: false          // был ли хоть один успешный ответ
    property string lastError: ""
    property real lastSuccess: 0         // Date.now() последнего успеха
    property string provider: ""         // откуда данные: open-meteo | yr

    property real visibilityM: -1        // видимость в метрах (Open-Meteo), −1 = данных нет
    property double lastRainMs: 0        // момент последнего «мокрого» состояния (для радуги)
    property int nowTick: 0              // тик раз в минуту — пересчёт условий, зависящих от времени

    // ---------- гонка запросов ----------
    property bool inflight: false        // идёт раунд опроса
    property bool won: false             // в этом раунде уже есть успех
    property int pending: 0              // сколько запросов ещё не завершено
    property var cancellers: []           // функции отмены текущего раунда

    // ---------- тестовые режимы ----------
    // Задаются переменной окружения ATMOSPHERIC_TEST (см. scripts/run.sh):
    //   rain | heavy-rain | drizzle | snow | fog | thunder | cloudy | night | clear
    // или в рантайме: qs -p /path/to/atmospheric ipc call weather test snow
    // Тест НЕ трогает реальные данные: API продолжает опрашиваться,
    // а effective*-свойства подменяют то, что рисует оверлей.
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
        return testMode === "" ? "test off (реальная погода)" : "test: " + testMode;
    }

    // Состояние без «украшений» (пока — радуги): данные или тест.
    readonly property string composedState: {
        switch (testMode) {
        case "":             return composeState(state);
        case "night":        return composeState(state);         // ночь — это isDay, состояние реальное
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
        case "hail":         return "thunder";                   // град идёт только с грозой
        case "thunder":
        case "storm":        return "thunder";
        case "rainbow":      return "rainbow";
        default:             return state;
        }
    }

    // Радуга: дождь кончился недавно, небо чистое, а солнце низко
    // (дуга видна только пока alt < 42° — физика первичного радуга).
    readonly property bool rainbowNow: {
        nowTick;                                 // время не реактивно — тик раз в минуту
        if (testMode !== "")
            return false;                        // в тесте rainbow задаётся кейсом выше
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

    // Что реально рисует оверлей (тест приоритетнее реальных данных).
    readonly property string effectiveState:
        (testMode === "" && rainbowNow) ? "rainbow" : composedState;

    // ---------- модификаторы текущего состояния ----------
    // Град в таблице WMO идёт только с грозой (коды 96/99).
    readonly property bool effectiveHail: {
        if (testMode === "hail") return true;
        return testMode === "" && (code === 96 || code === 99);
    }
    // Метель: снег + ветер сильнее порога.
    readonly property bool effectiveBlizzard: {
        if (testMode === "blizzard") return true;
        return testMode === "" && effectiveState === "snow"
               && windSpeed >= (cfg ? cfg.blizzardWind : 8);
    }
    // Густой туман по глубине видимости (коды 45/48 остаются основным сигналом).
    readonly property bool effectiveFogDense: {
        if (testMode === "fog-dense") return true;
        return testMode === "" && visibilityM >= 0
               && visibilityM < (cfg ? cfg.fogDenseVisibilityM : 300);
    }

    // Пока шёл дождь — запоминаем момент: он нужен для радуги.
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
            // Свежий радар видит осадки — интенсивность по серому уровню
            // пикселя (чёрный слабый, белый сильный); иначе от прогноза.
            if (radar.fresh && radar.precip)
                return Math.min(1, 0.3 + radar.gray * 0.7);
            return intensity;
        }
        if (testMode === "drizzle")   return 0.4;
        if (testMode === "rain")      return 0.7;
        if (testMode === "heavyrain" || testMode === "heavy-rain") return 1.0;
        return 0.7;
    }

    // В тесте без загруженных данных — лёгкий наклон, чтобы капли были видны.
    readonly property real effectiveTilt: (testing && !loaded) ? 8 : tilt

    // Наклон капель по ветру, градусы (±25).
    // wind_direction_10m — «откуда»: движение на восток = -sin(dir).
    readonly property real tilt: {
        var horizontal = -Math.sin(windDirection * Math.PI / 180) * windSpeed;
        return Math.max(-25, Math.min(25, horizontal * 1.2));
    }

    // ---------- радар RainViewer: слой «реального времени» осадков ----------
    // Прогноз (Yr) отдаёт осадки почасовыми бинами и «отстаёт» от жизни:
    // дождь прошёл — бин ещё час поливается. Радар — наблюдение каждые
    // 10 минут: свежий кадр с пикселем осадков включает дождь/снег, чистая
    // точка — гасит прогнозные бины. Туман/ветер/облачность радар не видит,
    // остаются от прогноза. В status: radar=on/3m | off/3m | stale | none.
    Radar {
        id: radar
        cfg: root.cfg
    }
    readonly property bool   radarFresh:     radar.fresh
    readonly property bool   radarPrecip:    radar.precip
    readonly property real   radarDecodedMs: radar.decodedMs
    readonly property string radarError:     radar.lastError

    // Сводка прогноза и радара в одно состояние оверлея (тест-режим — выше).
    function composeState(base) {
        if (!radar.fresh)
            return base;
        if (radar.precip) {
            if (base === "thunder")
                return "thunder";            // прогноз знает грозу — радар не отменяет
            if (temperature <= 0.5)
                return "snow";               // холод + радар = снег
            if (base === "drizzle" || base === "rain" || base === "heavyRain" || base === "sleet")
                return base;                 // интенсивность — от прогноза
            return "rain";                   // осадки начались раньше прогноза
        }
        // Радар чист: прогнозные ливни/снег/грозу/смешанные осадки гасим.
        // Морось (drizzle) оставляем — радар её почти не видит, а капли лёгкие.
        if (base === "rain" || base === "heavyRain" || base === "snow" || base === "thunder" || base === "sleet")
            return "cloudy";
        return base;
    }

    // Рисовать ли оверлей вообще (в тесте — всегда, кроме явного clear/off
    // и облачности: dimCloudy убран, облачность больше ничего не показывает).
    readonly property bool active: (loaded || testing) && (
        (effectiveState !== "clear" && effectiveState !== "cloudy")
        || effectiveIsDay === 0
        || (effectiveState === "cloudy" && cfg && cfg.dimCloudy)
    )

    // ---------- маппинг WMO ----------
    function stateFor(c) {
        if (c >= 0 && c <= 3)  return c <= 1 ? "clear" : "cloudy";
        if (c === 45 || c === 48) return "fog";
        if (c >= 51 && c <= 55) return "drizzle";           // морось
        if (c === 56 || c === 57 || c === 66 || c === 67)
            return "sleet";                                 // переохлаждённая морось/дождь → дождь со снегом
        if (c >= 61 && c <= 63) return "rain";
        if (c === 65) return "heavyRain";                   // ливень
        if (c === 80) return "rain";
        if (c >= 81 && c <= 82) return "heavyRain";         // сильные ливни
        if (c >= 71 && c <= 77) return "snow";
        if (c === 85 || c === 86) return "snow";
        if (c >= 95 && c <= 99) return "thunder";           // 96/99 — с градом (см. effectiveHail)
        return "cloudy";                                     // неизвестный код — аккуратное облако
    }

    function intensityFor(c) {
        if (c === 61 || c === 80) return 0.45;
        if (c === 63) return 0.7;
        if (c === 65) return 1.0;
        if (c === 56 || c === 66) return 0.35;              // дождь со снегом: лёгкий
        if (c === 57 || c === 67) return 0.9;               // дождь со снегом: плотный
        if (c === 81) return 0.85;
        if (c === 82) return 1.0;
        if (c >= 51 && c <= 55) return 0.3 + (c - 51) * 0.05;
        if (c === 85) return 0.6;
        if (c === 86) return 0.9;
        if (c >= 71 && c <= 77) return 0.4 + (c - 71) * 0.06;
        if (c >= 95) return 0.9;
        return 0.6;
    }

    // Символ Yr (met.no) → ближайший WMO-код, чтобы работал общий маппинг.
    function yrToWmo(sym) {
        var s = String(sym).toLowerCase();
        if (s.indexOf("thunder") !== -1) return s.indexOf("heavy") !== -1 ? 99 : 95;
        if (s.indexOf("snow") !== -1) {
            if (s.indexOf("heavy") !== -1) return s.indexOf("shower") !== -1 ? 86 : 75;
            if (s.indexOf("light") !== -1) return s.indexOf("shower") !== -1 ? 85 : 71;
            return s.indexOf("shower") !== -1 ? 85 : 73;
        }
        if (s.indexOf("sleet") !== -1 || s.indexOf("freezing") !== -1 || s.indexOf("wintry") !== -1)
            return s.indexOf("heavy") !== -1 ? 67 : 66;     // дождь со снегом
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

    // Высота Солнца в градусах (алгоритм SunCalc).
    // Сверено с api.met.no/weatherapi/sunrise для Орла (2026-10-15):
    // рассвет 07:01 = 07:01, закат 17:41 ≈ 17:40, высота в полдень ±0.2°.
    function sunAltitudeDeg(dateMs, lat, lon) {
        var rad = Math.PI / 180;
        var d = dateMs / 86400000 + 2440587.5 - 2451545.0;   // дней от J2000
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
            + "&hourly=visibility"                // второй сигнал тумана (в метрах, почасово)
            + "&wind_speed_unit=ms"
            + "&timezone=auto";
    }

    function yrEndpoint() {
        return "https://api.met.no/weatherapi/locationforecast/2.0/compact"
            + "?lat=" + cfg.latitude
            + "&lon=" + cfg.longitude;
    }

    // ---------- применение ответов ----------
    function commit() {
        loaded = true;
        lastSuccess = Date.now();
    }

    // open-meteo: data = полный ответ (current + hourly)
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

        // Туман по видимости — второй сигнал помимо кодов 45/48.
        // Видимость низкая и при сильном дожде/снегу — те состояния выше по приоритету.
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

    // met.no/Yr: data = полный Feature; WMO-кода нет — выводим из символа,
    // is_day считаем сами (в ответе Yr его нет).
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
            // Символа нет — облачность из instant.details.
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
        visibilityM = -1;                       // Yr видимости не отдаёт — сигнала тумана нет
        commit();
    }

    // ---------- гонка ----------
    // settle учитывает ровно один исход каждого запроса (флаг myDone в замыкании),
    // поэтому abort проигравшего не «досчитает» pending повторно.
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
            cancelRound();                       // проигравший: myDone → no-op + abort
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
            return;                              // идемпотентно
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
                        finish(true, d, "");    // applyOm нужен и hourly.visibility
                } catch (e) {
                    finish(false, null, "parse: " + e);
                }
            } else {
                // Сетевая ошибка: состояние не трогаем, остаётся последнее известное.
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
            // met.no просит осмысленный User-Agent; если Qt не даст заголовок —
            // сервер всё равно отвечает (проверено на живом инстансе).
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

    // Солнце/дата в биндингах не реактивны — тик раз в минуту, чтобы
    // условия вроде радуги пересчитывались вовремя.
    Timer {
        interval: 60 * 1000
        repeat: true
        running: true
        onTriggered: root.nowTick++
    }

    // Основной опрос: раз в refreshMinutes, первый — сразу при старте.
    // После каждого цикла к интервалу добавляется 0..2 мин случайной задержки —
    // Terms met.no просят не засекать трафик фиксированным расписанием.
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

    // Быстрый повтор: пока не загрузилось или после ошибки — каждую минуту.
    Timer {
        interval: 60 * 1000
        running: !root.loaded || root.lastError !== ""
        repeat: true
        onTriggered: root.refresh()
    }
}

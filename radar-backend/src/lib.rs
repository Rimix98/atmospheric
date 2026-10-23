// ============================================================
// atmospheric-radar — логика радара RainViewer (библиотека).
//
// Вынесена из QML, потому что Quickshell рисует Canvas только внутри
// видимого PanelWindow, а Weather/Radar висят в Scope (без окна) —
// onPaint не вызывался и тайл не декодировался. Здесь: сеть, выбор
// кадра, декод PNG, чтение alpha-пикселя точки — всё вне рендера.
//
// Контракт состояния для QML (JSON-строка через unix-сокет):
//   { "precip": bool, "intensity": 0..1, "fresh": bool,
//     "frame_ms": u64, "age_minutes": i64, "error": "" }
//
// Всё fail-open: недоступен RainViewer / битый кадр / тайл не
// загрузился — поле error заполнено и fresh=false, и QML работает
// по прогнозу, как раньше.
// ============================================================
use std::time::Duration;

use serde::Serialize;

/// Состояние радара, которое видит QML.
#[derive(Clone, Serialize, Default)]
pub struct RadarState {
    /// Осадки в точке прямо сейчас (alpha пикселя > 8).
    pub precip: bool,
    /// Интенсивность 0..1 по серому уровню пикселя (чёрный — слабый, белый — сильный).
    pub intensity: f64,
    /// Кадр разобран и не старше radarMaxAgeMinutes.
    pub fresh: bool,
    /// Эпоха (мс) разобранного кадра RainViewer.
    pub frame_ms: u64,
    /// Возраст кадра в минутах (для status radar=on/4m).
    pub age_minutes: i64,
    /// Последняя короткая причина отказа ("" — нет): "fetch-list", "fetch-tile"…
    pub error: String,
}

pub const FRAME_LIST_URL: &str = "https://api.rainviewer.com/public/weather-maps.json";
pub const TILE_HOST_FALLBACK: &str = "https://tilecache.rainviewer.com";
pub const ZOOM: i32 = 10;

// ------------------------------------------------------------
// Один проход: список кадров → (при необходимости) тайл → декод → пиксель точки.
// ------------------------------------------------------------
pub fn poll_once(lat: f64, lon: f64, max_age_minutes: i64, prev: &RadarState) -> RadarState {
    let now_ms = now_epoch_ms();

    // 1) Список кадров RainViewer (~10 КБ).
    let frames_json = match fetch_text(FRAME_LIST_URL) {
        Ok(t) => t,
        Err(e) => {
            eprintln!("[radar] список кадров: {e}");
            return error_state(prev, now_ms, "fetch-list");
        }
    };
    let v: serde_json::Value = match serde_json::from_str(&frames_json) {
        Ok(v) => v,
        Err(e) => {
            eprintln!("[radar] JSON списка кадров: {e}");
            return error_state(prev, now_ms, "parse-list");
        }
    };
    let host = v["host"]
        .as_str()
        .unwrap_or(TILE_HOST_FALLBACK)
        .trim_end_matches('/')
        .to_string();
    let past = v["radar"]["past"].as_array().cloned().unwrap_or_default();
    let Some(last) = past.iter().max_by_key(|f| f["time"].as_u64().unwrap_or(0)) else {
        eprintln!("[radar] в списке нет прошлых кадров");
        return error_state(prev, now_ms, "no-frames");
    };
    // time у RainViewer — секунды, QML сравнивает с Date.now() (мс).
    let frame_ms = last["time"].as_u64().unwrap_or(0) * 1000;
    let path = last["path"].as_str().unwrap_or("");

    let age_minutes = if frame_ms > 0 && now_ms > frame_ms {
        ((now_ms - frame_ms) / 60_000) as i64
    } else {
        0
    };
    let fresh = age_minutes <= max_age_minutes;

    // Тот же кадр, что уже разобран, и ошибок не было — тайл не перечитываем
    // (кадры RainViewer обновляются раз в 10 минут, а список опрашиваем чаще).
    if frame_ms > 0 && frame_ms == prev.frame_ms && prev.error.is_empty() {
        return RadarState { fresh, age_minutes, ..prev.clone() };
    }

    // 2) Тайл района (z=10, 256×256, ~250 м/пиксель).
    let tile_url =
        format!("{host}{path}/256/{ZOOM}/{}/{}/4/1_1.png", tile_x(lon), tile_y(lat));
    let png_bytes = match fetch_bytes(&tile_url) {
        Ok(b) => b,
        Err(e) => {
            eprintln!("[radar] тайл: {e}");
            return error_state(prev, now_ms, "fetch-tile");
        }
    };

    // 3) Декод PNG и чтение пикселя точки.
    match decode_pixel(&png_bytes, pixel_x(lon), pixel_y(lat)) {
        Ok((precip, intensity)) => RadarState {
            precip,
            intensity,
            fresh,
            frame_ms,
            age_minutes,
            error: String::new(),
        },
        Err(e) => {
            eprintln!("[radar] декод тайла: {e}");
            error_state(prev, now_ms, "decode-tile")
        }
    }
}

/// Состояние при отказе: свежесть гасим (QML уходит на чистый прогноз),
/// прежние значения и возраст кадра сохраняем для status radar=stale!…
fn error_state(prev: &RadarState, now_ms: u64, msg: &str) -> RadarState {
    let age_minutes = if prev.frame_ms > 0 && now_ms > prev.frame_ms {
        ((now_ms - prev.frame_ms) / 60_000) as i64
    } else {
        prev.age_minutes
    };
    RadarState {
        fresh: false,
        age_minutes,
        error: msg.to_string(),
        ..prev.clone()
    }
}

// ------------------------------------------------------------
// Геометрия тайла (web-mercator, XYZ как в OSM/RainViewer).
// ------------------------------------------------------------
pub fn tile_x(lon: f64) -> i64 {
    let n = (1 << ZOOM) as f64;
    (((lon + 180.0) / 360.0) * n).floor() as i64
}

pub fn tile_y(lat: f64) -> i64 {
    let n = (1 << ZOOM) as f64;
    let phi = lat.to_radians();
    (((1.0 - ((phi.tan() + 1.0 / phi.cos()).ln() / std::f64::consts::PI)) / 2.0) * n).floor() as i64
}

pub fn pixel_x(lon: f64) -> u32 {
    let n = (1 << ZOOM) as f64;
    let xf = ((lon + 180.0) / 360.0) * n;
    (((xf - xf.floor()) * 256.0).round() as u32).min(255)
}

pub fn pixel_y(lat: f64) -> u32 {
    let n = (1 << ZOOM) as f64;
    let phi = lat.to_radians();
    let yf = ((1.0 - ((phi.tan() + 1.0 / phi.cos()).ln() / std::f64::consts::PI)) / 2.0) * n;
    (((yf - yf.floor()) * 256.0).round() as u32).min(255)
}

// ------------------------------------------------------------
// Декод PNG → (осадки, интенсивность 0..1).
// ------------------------------------------------------------
pub fn decode_pixel(bytes: &[u8], px: u32, py: u32) -> Result<(bool, f64), String> {
    let mut decoder = png::Decoder::new(std::io::Cursor::new(bytes));
    // Палитры/16 бит/малая глубина → на выходе всегда 8-битные
    // Grayscale / GrayscaleAlpha / Rgb / Rgba.
    decoder.set_transformations(png::Transformations::normalize_to_color8());
    let mut reader = decoder.read_info().map_err(|e| e.to_string())?;
    let mut buf = vec![0u8; reader.output_buffer_size().ok_or("пустой кадр")?];
    let info = reader.next_frame(&mut buf).map_err(|e| e.to_string())?;
    let data = &buf[..info.buffer_size()];
    let (w, h) = (info.width, info.height);
    if w == 0 || h == 0 || px >= w || py >= h {
        return Err(format!("пиксель ({px},{py}) вне тайла {w}×{h}"));
    }

    let idx = (py as usize) * (w as usize) + (px as usize);
    let (r, g, b, a): (u8, u8, u8, u8) = match info.color_type {
        png::ColorType::Rgba => {
            let i = idx * 4;
            (data[i], data[i + 1], data[i + 2], data[i + 3])
        }
        png::ColorType::Rgb => {
            let i = idx * 3;
            (data[i], data[i + 1], data[i + 2], 255)
        }
        png::ColorType::GrayscaleAlpha => {
            let i = idx * 2;
            (data[i], data[i], data[i], data[i + 1])
        }
        png::ColorType::Grayscale => (data[idx], data[idx], data[idx], 255),
        other => return Err(format!("неподдерживаемый формат {other:?}")),
    };

    let precip = a > 8;
    // Серый пиксель (r=g=b) — уровень интенсивности; цветной палитре — 0.5.
    let intensity = if r == g && g == b { r as f64 / 255.0 } else { 0.5 };
    Ok((precip, intensity))
}

// ------------------------------------------------------------
// Сеть.
// ------------------------------------------------------------
const USER_AGENT: &str = "atmospheric-radar/1.0 (quickshell overlay)";

pub fn fetch_text(url: &str) -> Result<String, String> {
    let mut resp = ureq::get(url)
        .header("User-Agent", USER_AGENT)
        .config()
        .timeout_global(Some(Duration::from_secs(15)))
        .build()
        .call()
        .map_err(|e| e.to_string())?;
    resp.body_mut().read_to_string().map_err(|e| e.to_string())
}

pub fn fetch_bytes(url: &str) -> Result<Vec<u8>, String> {
    let mut resp = ureq::get(url)
        .header("User-Agent", USER_AGENT)
        .config()
        .timeout_global(Some(Duration::from_secs(15)))
        .build()
        .call()
        .map_err(|e| e.to_string())?;
    resp.body_mut().read_to_vec().map_err(|e| e.to_string())
}

pub fn now_epoch_ms() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

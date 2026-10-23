// ============================================================
// atmospheric-radar — RainViewer radar logic (library).
//
// Extracted from QML because Quickshell only draws Canvas inside
// a visible PanelWindow, while Weather/Radar live in a Scope (no
// window) — onPaint never fired and the tile was never decoded.
// Here: network, frame selection, PNG decode, point pixel read —
// all outside the render.
//
// State contract for QML (JSON string over a unix socket):
//   { "precip": bool, "intensity": 0..1, "fresh": bool,
//     "frame_ms": u64, "age_minutes": i64, "error": "" }
//
// Everything fail-open: RainViewer unreachable / broken frame /
// tile failed to load — error is filled and fresh=false, and QML
// falls back to the forecast as before.
// ============================================================
use std::time::Duration;

use serde::Serialize;

/// Radar state as seen by QML.
#[derive(Clone, Serialize, Default)]
pub struct RadarState {
    /// Precipitation at the point right now (alpha pixel > 8).
    pub precip: bool,
    /// Intensity 0..1 from the pixel gray level (black — weak, white — strong).
    pub intensity: f64,
    /// Frame decoded and not older than radarMaxAgeMinutes.
    pub fresh: bool,
    /// Epoch (ms) of the decoded RainViewer frame.
    pub frame_ms: u64,
    /// Frame age in minutes (for status radar=on/4m).
    pub age_minutes: i64,
    /// Last short failure reason ("" — none): "fetch-list", "fetch-tile"…
    pub error: String,
}

pub const FRAME_LIST_URL: &str = "https://api.rainviewer.com/public/weather-maps.json";
pub const TILE_HOST_FALLBACK: &str = "https://tilecache.rainviewer.com";
pub const ZOOM: i32 = 10;

// ------------------------------------------------------------
// One pass: frame list → (if needed) tile → decode → point pixel.
// ------------------------------------------------------------
pub fn poll_once(lat: f64, lon: f64, max_age_minutes: i64, prev: &RadarState) -> RadarState {
    let now_ms = now_epoch_ms();

    // 1) RainViewer frame list (~10 KB).
    let frames_json = match fetch_text(FRAME_LIST_URL) {
        Ok(t) => t,
        Err(e) => {
            eprintln!("[radar] frame list: {e}");
            return error_state(prev, now_ms, "fetch-list");
        }
    };
    let v: serde_json::Value = match serde_json::from_str(&frames_json) {
        Ok(v) => v,
        Err(e) => {
            eprintln!("[radar] frame list JSON: {e}");
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
        eprintln!("[radar] no past frames in list");
        return error_state(prev, now_ms, "no-frames");
    };
    // RainViewer time is in seconds; QML compares it with Date.now() (ms).
    let frame_ms = last["time"].as_u64().unwrap_or(0) * 1000;
    let path = last["path"].as_str().unwrap_or("");

    let age_minutes = if frame_ms > 0 && now_ms > frame_ms {
        ((now_ms - frame_ms) / 60_000) as i64
    } else {
        0
    };
    let fresh = age_minutes <= max_age_minutes;

    // Same frame as already decoded and no errors — skip re-reading the
    // tile (RainViewer frames update every 10 min, but we poll the list more often).
    if frame_ms > 0 && frame_ms == prev.frame_ms && prev.error.is_empty() {
        return RadarState { fresh, age_minutes, ..prev.clone() };
    }

    // 2) Area tile (z=10, 256×256, ~250 m/pixel).
    let tile_url =
        format!("{host}{path}/256/{ZOOM}/{}/{}/4/1_1.png", tile_x(lon), tile_y(lat));
    let png_bytes = match fetch_bytes(&tile_url) {
        Ok(b) => b,
        Err(e) => {
            eprintln!("[radar] tile: {e}");
            return error_state(prev, now_ms, "fetch-tile");
        }
    };

    // 3) Decode PNG and read the point pixel.
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
            eprintln!("[radar] tile decode: {e}");
            error_state(prev, now_ms, "decode-tile")
        }
    }
}

/// Failure state: freshness cleared (QML falls back to the plain forecast),
/// previous values and frame age kept for status radar=stale!…
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
// Tile geometry (web mercator, XYZ as in OSM/RainViewer).
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
// Decode PNG → (precip, intensity 0..1).
// ------------------------------------------------------------
pub fn decode_pixel(bytes: &[u8], px: u32, py: u32) -> Result<(bool, f64), String> {
    let mut decoder = png::Decoder::new(std::io::Cursor::new(bytes));
    // Palettes / 16 bit / low depth → the output is always 8-bit
    // Grayscale / GrayscaleAlpha / Rgb / Rgba.
    decoder.set_transformations(png::Transformations::normalize_to_color8());
    let mut reader = decoder.read_info().map_err(|e| e.to_string())?;
    let mut buf = vec![0u8; reader.output_buffer_size().ok_or("empty frame")?];
    let info = reader.next_frame(&mut buf).map_err(|e| e.to_string())?;
    let data = &buf[..info.buffer_size()];
    let (w, h) = (info.width, info.height);
    if w == 0 || h == 0 || px >= w || py >= h {
        return Err(format!("pixel ({px},{py}) outside tile {w}×{h}"));
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
        other => return Err(format!("unsupported format {other:?}")),
    };

    let precip = a > 8;
    // Gray pixel (r=g=b) — intensity level; colored palette — 0.5.
    let intensity = if r == g && g == b { r as f64 / 255.0 } else { 0.5 };
    Ok((precip, intensity))
}

// ------------------------------------------------------------
// Networking.
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

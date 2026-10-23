// Дымовой тест демона: без сокета, один проход опроса RainViewer в stdout.
// Проверяет сеть, выбор кадра и декод PNG на живых данных:
//   cargo run --release --bin smoke -- 52.9668 36.0625
use atmospheric_radar::{poll_once, RadarState};

fn main() {
    let lat: f64 = std::env::args().nth(1).and_then(|s| s.parse().ok()).unwrap_or(52.9668);
    let lon: f64 = std::env::args().nth(2).and_then(|s| s.parse().ok()).unwrap_or(36.0625);
    let st = poll_once(lat, lon, 25, &RadarState::default());
    println!("{}", serde_json::to_string_pretty(&st).unwrap());
    if st.error.is_empty() {
        eprintln!("OK: сеть + декод PNG отработали");
    } else {
        eprintln!("ERROR: {}", st.error);
        std::process::exit(1);
    }
}

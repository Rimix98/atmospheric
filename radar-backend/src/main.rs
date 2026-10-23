// ============================================================
// atmospheric-radar — RainViewer radar daemon for the atmospheric overlay.
//
// Why Rust instead of Canvas in QML: Quickshell only draws Canvas inside
// a visible PanelWindow, while Weather/Radar live in a Scope (no window) —
// onPaint never fires and the tile is never decoded. Here the PNG decode
// runs outside the render (all logic lives in lib.rs).
//
// Daemon role: unix server. Loop once per second:
//   1) accepts new QML clients and immediately sends the current state;
//   2) polls RainViewer on schedule (frame list → tile → decode →
//      point alpha pixel);
//   3) broadcasts the updated JSON to all clients.
//
// Singleton: if someone already listens on the socket path — a second
// instance exits (needed for QML hot-reload, when the old daemon is
// not yet killed).
//
// Args: <socket> [lat] [lon] [poll_minutes] [max_age_minutes]
// ============================================================
use std::io::{ErrorKind, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::PathBuf;
use std::time::{Duration, Instant};

use atmospheric_radar::{poll_once, RadarState};

fn main() {
    let mut args = std::env::args().skip(1);
    let sock_path = PathBuf::from(
        args.next().unwrap_or_else(|| "/tmp/atmospheric-radar.sock".to_string()),
    );
    let lat: f64 = args.next().and_then(|s| s.parse().ok()).unwrap_or(52.9668);
    let lon: f64 = args.next().and_then(|s| s.parse().ok()).unwrap_or(36.0625);
    let poll_minutes: f64 = args.next().and_then(|s| s.parse().ok()).unwrap_or(3.0);
    let max_age: i64 = args.next().and_then(|s| s.parse().ok()).unwrap_or(25);
    // Guard against request storms when poll is 0 in the config.
    let poll_secs = (poll_minutes * 60.0).max(30.0);

    // ---------- singleton ----------
    match UnixStream::connect(&sock_path) {
        Ok(_) => {
            eprintln!("[radar] daemon already running ({}) — exiting", sock_path.display());
            return;
        }
        Err(_) => {
            // Stale socket file left by a killed daemon — remove it.
            let _ = std::fs::remove_file(&sock_path);
        }
    }
    if let Some(dir) = sock_path.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    let listener = match UnixListener::bind(&sock_path) {
        Ok(l) => l,
        Err(e) => {
            eprintln!("[radar] bind {}: {e}", sock_path.display());
            return;
        }
    };
    // Non-blocking accept: the loop must not stall on connections.
    let _ = listener.set_nonblocking(true);

    eprintln!(
        "[radar] start: point ({lat}, {lon}), poll {poll_minutes} min, max age {max_age} min, socket {}",
        sock_path.display()
    );

    let mut clients: Vec<UnixStream> = Vec::new();
    let mut state = RadarState::default();
    let mut next_poll = Instant::now(); // first poll immediately

    loop {
        // 1) new QML connections: send the current state
        loop {
            match listener.accept() {
                Ok((stream, _)) => {
                    if send_line(&stream, &state).is_ok() {
                        clients.push(stream);
                    }
                }
                Err(e) if e.kind() == ErrorKind::WouldBlock => break,
                Err(e) => {
                    eprintln!("[radar] accept: {e}");
                    break;
                }
            }
        }

        // 2) poll RainViewer on schedule
        if Instant::now() >= next_poll {
            let new = poll_once(lat, lon, max_age, &state);
            if new.frame_ms != state.frame_ms
                || new.error != state.error
                || new.precip != state.precip
            {
                eprintln!(
                    "[radar] frame {} ({} min ago): precip {}, intensity {:.2}{}",
                    new.frame_ms,
                    new.age_minutes,
                    if new.precip { "yes" } else { "no" },
                    new.intensity,
                    if new.error.is_empty() {
                        String::new()
                    } else {
                        format!(", error {}", new.error)
                    }
                );
            }
            state = new;

            // 3) broadcast to all clients; dropped ones (QML reloaded)
            // leave the list on EPIPE at the next poll
            clients.retain(|c| send_line(c, &state).is_ok());

            next_poll = Instant::now() + Duration::from_secs_f64(poll_secs);
        }

        std::thread::sleep(Duration::from_secs(1));
    }
}

/// One JSON state line + '\n' (SplitParser on the other side splits on \n).
fn send_line(stream: &UnixStream, st: &RadarState) -> std::io::Result<()> {
    let mut line = serde_json::to_string(st).map_err(std::io::Error::other)?;
    line.push('\n');
    let mut w = stream; // Write is implemented for &UnixStream
    w.write_all(line.as_bytes())?;
    w.flush()
}

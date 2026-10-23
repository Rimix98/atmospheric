// ============================================================
// atmospheric-radar — демон радара RainViewer для оверлея atmospheric.
//
// Зачем Rust, а не Canvas в QML: Quickshell рисует Canvas только внутри
// видимого PanelWindow, а Weather/Radar висят в Scope (без окна) —
// onPaint не вызывался и тайл не декодируется. Здесь декод PNG идёт
// вне рендера (вся логика — в lib.rs).
//
// Роль демона: unix-сервер. Цикл раз в секунду:
//   1) принимает новых клиентов QML и сразу отдаёт текущий срез;
//   2) по расписанию опрашивает RainViewer (список кадров → тайл →
//      декод → alpha-пиксель точки);
//   3) рассылает обновлённый JSON всем клиентам.
//
// Одиночка: если по пути сокета уже кто-то слушает — второй экземпляр
// выходит (нужно при hot-reload QML, когда старый демон ещё не убит).
//
// Аргументы: <сокет> [широта] [долгота] [опрос_мин] [свежесть_мин]
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
    // Не даём устроить шторм запросов при опросе 0 в конфиге.
    let poll_secs = (poll_minutes * 60.0).max(30.0);

    // ---------- одиночка ----------
    match UnixStream::connect(&sock_path) {
        Ok(_) => {
            eprintln!("[radar] демон уже запущен ({}) — выхожу", sock_path.display());
            return;
        }
        Err(_) => {
            // Файл сокета остался от убитого демона — убираем.
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
    // Неблокирующий accept: цикл не должен вставать на подключении.
    let _ = listener.set_nonblocking(true);

    eprintln!(
        "[radar] старт: точка ({lat}, {lon}), опрос {poll_minutes} мин, свежесть {max_age} мин, сокет {}",
        sock_path.display()
    );

    let mut clients: Vec<UnixStream> = Vec::new();
    let mut state = RadarState::default();
    let mut next_poll = Instant::now(); // первый опрос — сразу

    loop {
        // 1) новые подключения QML: отдаём текущий срез
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

        // 2) опрос RainViewer по расписанию
        if Instant::now() >= next_poll {
            let new = poll_once(lat, lon, max_age, &state);
            if new.frame_ms != state.frame_ms
                || new.error != state.error
                || new.precip != state.precip
            {
                eprintln!(
                    "[radar] кадр {} ({} мин назад): осадки {}, интенсивность {:.2}{}",
                    new.frame_ms,
                    new.age_minutes,
                    if new.precip { "да" } else { "нет" },
                    new.intensity,
                    if new.error.is_empty() {
                        String::new()
                    } else {
                        format!(", ошибка {}", new.error)
                    }
                );
            }
            state = new;

            // 3) рассылка всем клиентам; отвалившиеся (QML перезагрузился)
            // уходят из списка по EPIPE на следующем опросе
            clients.retain(|c| send_line(c, &state).is_ok());

            next_poll = Instant::now() + Duration::from_secs_f64(poll_secs);
        }

        std::thread::sleep(Duration::from_secs(1));
    }
}

/// Одна JSON-строка состояния + '\n' (SplitParser на той стороне режет по \n).
fn send_line(stream: &UnixStream, st: &RadarState) -> std::io::Result<()> {
    let mut line = serde_json::to_string(st).map_err(std::io::Error::other)?;
    line.push('\n');
    let mut w = stream; // Write реализован для &UnixStream
    w.write_all(line.as_bytes())?;
    w.flush()
}

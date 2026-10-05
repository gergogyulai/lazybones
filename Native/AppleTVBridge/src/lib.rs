//! A C ABI over atv-core, for Lazybones to load at runtime.
//!
//! Lazybones advertises itself as an Apple TV; the iPhone's Control Center remote pairs with it and
//! sends buttons and touches, which arrive here and go straight to one callback. The touch surface
//! runs in atv-core's mouse mode, so Lazybones gets the raw finger and makes swipes itself, the
//! same way it does for the Siri Remote.

use std::ffi::{c_char, c_void, CStr, CString};
use std::sync::Arc;

use atv_core::{AtvConfig, AtvDelegate, AtvServer, EventKind, TouchPhase, TrackpadMode};
use tokio::runtime::Runtime;

/// What a callback reports. Keep in step with `PhoneRemote.Kind` in Swift.
#[repr(u32)]
#[derive(Clone, Copy)]
enum Kind {
    /// A button let go. Text: atv-core's name for it ("up", "menu", "play_pause"...).
    Button = 0,
    /// A finger down on the touch surface.
    TouchBegan = 1,
    /// The finger moved by (x, y), in surface units (1000 across, y down).
    TouchMoved = 2,
    /// The finger lifted.
    TouchEnded = 3,
    /// A tap on the touch surface.
    Tap = 4,
    /// A phone started pairing. Text: the PIN it must enter.
    PairingStarted = 5,
    /// Pairing finished.
    Paired = 6,
    /// A phone's remote session started. Text: the phone's address.
    Connected = 7,
    /// A phone went away.
    Disconnected = 8,
    /// A line of atv-core's log. Text: the line, with its level.
    Log = 9,
}

type Callback = extern "C" fn(ctx: *mut c_void, kind: u32, text: *const c_char, x: f64, y: f64);

#[derive(Clone, Copy)]
struct Sink {
    callback: Callback,
    ctx: *mut c_void,
}

// The context is Lazybones's, which is safe to call from any thread.
unsafe impl Send for Sink {}
unsafe impl Sync for Sink {}

impl Sink {
    fn send(&self, kind: Kind, text: &str, x: f64, y: f64) {
        let text = CString::new(text).unwrap_or_default();
        (self.callback)(self.ctx, kind as u32, text.as_ptr(), x, y);
    }
}

/// Where atv-core's log goes: the running server's callback, if there is one.
static LOG: std::sync::Mutex<Option<Sink>> = std::sync::Mutex::new(None);

struct LogWriter;

impl std::io::Write for LogWriter {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        let line = String::from_utf8_lossy(buf);
        let line = line.trim_end();
        if let Some(sink) = *LOG.lock().unwrap_or_else(|e| e.into_inner()) {
            if !line.is_empty() {
                sink.send(Kind::Log, line, 0.0, 0.0);
            }
        }
        Ok(buf.len())
    }

    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

/// Sends atv-core's log (connections, pairing, what it registered where) to Lazybones's.
fn forward_log(sink: Option<Sink>, verbose: bool) {
    *LOG.lock().unwrap_or_else(|e| e.into_inner()) = sink;
    static INSTALLED: std::sync::Once = std::sync::Once::new();
    INSTALLED.call_once(|| {
        let _ = tracing_subscriber::fmt()
            .with_max_level(if verbose { tracing::Level::DEBUG } else { tracing::Level::INFO })
            .with_writer(|| LogWriter)
            .with_ansi(false)
            .without_time()
            .with_target(false)
            .try_init();
    });
}

struct Delegate(Sink);

impl AtvDelegate for Delegate {
    fn on_button(&self, name: &str) {
        self.0.send(Kind::Button, name, 0.0, 0.0);
    }

    fn on_touch(&self, dx: f64, dy: f64, phase: TouchPhase) {
        match phase {
            TouchPhase::Began => self.0.send(Kind::TouchBegan, "", 0.0, 0.0),
            TouchPhase::Moved => self.0.send(Kind::TouchMoved, "", dx, dy),
            TouchPhase::Ended => self.0.send(Kind::TouchEnded, "", dx, dy),
        }
    }

    fn on_event(&self, kind: EventKind, detail: &str) {
        match kind {
            EventKind::MouseClick => self.0.send(Kind::Tap, "", 0.0, 0.0),
            EventKind::Paired => self.0.send(Kind::Paired, "", 0.0, 0.0),
            EventKind::RemoteReady => self.0.send(Kind::Connected, detail, 0.0, 0.0),
            EventKind::ClientDisconnected => self.0.send(Kind::Disconnected, detail, 0.0, 0.0),
            _ => {}
        }
    }

    // Mouse mode only so the touches come through raw; nothing here moves the Mac's pointer.
    fn get_touchpad_settings(&self) -> (f64, bool, bool) {
        (1.0, false, false)
    }
}

pub struct Handle {
    runtime: Runtime,
    server: Option<AtvServer>,
}

fn string(p: *const c_char) -> Option<String> {
    if p.is_null() {
        return None;
    }
    let s = unsafe { CStr::from_ptr(p) }.to_string_lossy().trim().to_string();
    (!s.is_empty()).then_some(s)
}

fn write_error(buf: *mut c_char, len: usize, message: &str) {
    if buf.is_null() || len == 0 {
        return;
    }
    let bytes = message.as_bytes();
    let n = bytes.len().min(len - 1);
    unsafe {
        std::ptr::copy_nonoverlapping(bytes.as_ptr(), buf as *mut u8, n);
        *buf.add(n) = 0;
    }
}

/// Starts advertising `name` and answering the phone. Returns null on failure, with the reason in
/// `error`. `server_id` (a UUID) and `device_id` (a MAC address) are the device's identity: keep
/// them the same from launch to launch, or the phone has to pair again. `address` (may be null) is
/// the LAN address to report. `verbose` logs every
/// protocol message too (decided by the first start; the log can't change level after).
#[no_mangle]
pub extern "C" fn lb_atv_start(
    name: *const c_char,
    server_id: *const c_char,
    device_id: *const c_char,
    pin: u32,
    address: *const c_char,
    verbose: bool,
    callback: Callback,
    ctx: *mut c_void,
    error: *mut c_char,
    error_len: usize,
) -> *mut Handle {
    let Some(name) = string(name) else {
        write_error(error, error_len, "no name");
        return std::ptr::null_mut();
    };
    let runtime = match tokio::runtime::Builder::new_multi_thread()
        .worker_threads(2)
        .thread_name("lazybones-atv")
        .enable_all()
        .build()
    {
        Ok(r) => r,
        Err(e) => {
            write_error(error, error_len, &e.to_string());
            return std::ptr::null_mut();
        }
    };

    // atv-core registers with Bonjour through `dns-sd` children, which outlive Lazybones if it
    // crashes or is killed and would keep a dead Apple TV in the phone's list. Clear any left from
    // last time, and leave a watcher to clear this run's once Lazybones is gone, however it ends.
    let registrations = format!("^/usr/bin/dns-sd -R {name} ");
    let _ = std::process::Command::new("/usr/bin/pkill").args(["-f", &registrations]).status();
    static WATCHER: std::sync::Once = std::sync::Once::new();
    WATCHER.call_once(|| {
        let me = std::process::id();
        let _ = std::process::Command::new("/bin/sh")
            .arg("-c")
            .arg(format!(
                "while /bin/kill -0 {me} 2>/dev/null; do /bin/sleep 2; done; /usr/bin/pkill -f '{registrations}'"
            ))
            .stdin(std::process::Stdio::null())
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .spawn();
    });

    let config = AtvConfig {
        name,
        pin: pin.min(9999),
        // On macOS only for the log: Bonjour gives each interface its own address. Left to itself,
        // atv-core names whichever has the default route, which may be a VPN's.
        ip: string(address).and_then(|a| a.parse().ok()),
        mouse_mode: true,
        trackpad_mode: TrackpadMode::Mouse,
        ui_port: None,
        mouse_speed: 1.0,
        device_id: string(device_id),
        server_identifier: string(server_id),
        private_key: None,
    };
    let sink = Sink { callback, ctx };
    forward_log(Some(sink), verbose);
    let started = runtime.block_on(AtvServer::start(config, Arc::new(Delegate(sink))));
    let server = match started {
        Ok(s) => s,
        Err(e) => {
            forward_log(None, verbose);
            write_error(error, error_len, &e.to_string());
            return std::ptr::null_mut();
        }
    };

    // The phone asks for the PIN when pairing starts, which atv-core reports only to its inspector.
    let (_, mut events) = server.inspector().subscribe();
    let pin = format!("{:04}", server.config().pin);
    runtime.spawn(async move {
        use tokio::sync::broadcast::error::RecvError;
        loop {
            match events.recv().await {
                Ok(e) if e.contains("\"pair_setup_m1\"") => sink.send(Kind::PairingStarted, &pin, 0.0, 0.0),
                Ok(_) | Err(RecvError::Lagged(_)) => {}
                Err(RecvError::Closed) => break,
            }
        }
    });

    Box::into_raw(Box::new(Handle { runtime, server: Some(server) }))
}

/// Stops advertising and drops every phone. No callbacks arrive once it returns.
#[no_mangle]
pub extern "C" fn lb_atv_stop(handle: *mut Handle) {
    if handle.is_null() {
        return;
    }
    let mut handle = unsafe { Box::from_raw(handle) };
    forward_log(None, false);
    if let Some(server) = handle.server.take() {
        handle.runtime.block_on(server.stop());
    }
    handle.runtime.shutdown_timeout(std::time::Duration::from_secs(1));
}

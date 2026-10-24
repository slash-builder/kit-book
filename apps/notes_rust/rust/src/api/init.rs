/// Runs once when the Dart side calls `RustLib.init()`.
#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    // Default utilities: a panic hook that reports to Dart, and a logger.
    flutter_rust_bridge::setup_default_user_utils();
}

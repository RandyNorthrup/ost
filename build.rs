// The audio feature builds a small C++ bridge to the system's WebRTC
// AudioProcessing library (echo cancellation, noise suppression, gain).
fn main() {
    println!("cargo::rerun-if-changed=src/calling/native/apm.cpp");
    if std::env::var_os("CARGO_FEATURE_AUDIO").is_none() {
        return;
    }
    let lib = pkg_config::Config::new()
        .atleast_version("1.0")
        .probe("webrtc-audio-processing-1")
        .expect("webrtc-audio-processing-1 (install its development package)");
    let mut build = cc::Build::new();
    build.cpp(true).std("c++17").file("src/calling/native/apm.cpp").warnings(false);
    for p in &lib.include_paths {
        build.include(p);
    }
    for (k, v) in &lib.defines {
        build.define(k, v.as_deref());
    }
    build.compile("ost_apm");
}

// The audio feature builds a small C++ bridge to the system's WebRTC
// AudioProcessing library (echo cancellation, noise suppression, gain):
// webrtc-audio-processing-1, or -2 where only that is installed (the
// Flatpak runtime ships -2).
fn main() {
    println!("cargo::rerun-if-changed=src/calling/native/apm.cpp");
    if std::env::var_os("CARGO_FEATURE_AUDIO").is_none() {
        return;
    }
    let probe = |name: &str, min: &str, link: bool| {
        pkg_config::Config::new()
            .atleast_version(min)
            .cargo_metadata(link)
            .probe(name)
    };
    let (name, min) = [
        ("webrtc-audio-processing-1", "1.0"),
        ("webrtc-audio-processing-2", "2.0"),
    ]
    .into_iter()
    .find(|(name, min)| probe(name, min, false).is_ok())
    .expect("webrtc-audio-processing-1 or -2 (install its development package)");
    let lib = probe(name, min, false).expect("webrtc-audio-processing");
    let mut build = cc::Build::new();
    build
        .cpp(true)
        .std("c++17")
        .file("src/calling/native/apm.cpp")
        .warnings(false);
    for p in &lib.include_paths {
        build.include(p);
    }
    for (k, v) in &lib.defines {
        build.define(k, v.as_deref());
    }
    build.compile("ost_apm");
    // The library's link flags after the bridge's: GNU ld (Ubuntu's Rust
    // links with it) only takes a shared library that an earlier input
    // needs, so it must come after ost_apm.
    probe(name, min, true).expect("webrtc-audio-processing");
}

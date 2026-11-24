//! Read, or set, your Editor spellcheck languages through AugLoop (debugging
//! aid): `cargo run --example editor_settings [-- '["en-us"]']`.
use teams_cli::api::editor::{Editor, Event};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let set: Option<Vec<String>> = std::env::args().nth(1).map(|a| serde_json::from_str(&a)).transpose()?;
    let ed = Editor::start(&tokio::runtime::Handle::current(), "en-us", |e| {
        if let Event::Settings(s) = e {
            println!("settings: {s:?}");
        }
    });
    if let Some(l) = set {
        ed.set_languages(l);
        tokio::time::sleep(std::time::Duration::from_secs(6)).await;
    }
    ed.read_settings();
    tokio::time::sleep(std::time::Duration::from_secs(6)).await;
    Ok(())
}

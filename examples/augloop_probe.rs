//! Teams' Editor (api::editor) live: check a text, then fix a word and
//! delete one, printing the critiques each time (debugging aid):
//! `cargo run --example augloop_probe`.
use teams_cli::api::editor::{Editor, Event};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let ed = Editor::start(&tokio::runtime::Handle::current(), "en-us", |e| match e {
        Event::Critiques { doc, critiques } => {
            let v: Vec<_> = critiques.iter().map(|c| format!("{}@{}+{}→{:?}", c.word, c.start, c.length, c.suggestions.first())).collect();
            println!("{doc}: {v:?}");
        }
        Event::Settings(s) => println!("settings: {s:?}"),
    });
    let step = |s: u64| tokio::time::sleep(std::time::Duration::from_secs(s));
    ed.set_text("chat", "Thsi is a tset of teh speling");
    step(6).await;
    println!("-- fix Thsi");
    ed.set_text("chat", "This is a tset of teh speling");
    step(4).await;
    println!("-- delete 'of teh '");
    ed.set_text("chat", "This is a tset speling");
    step(4).await;
    println!("-- second box");
    ed.set_text("other", "Anothr box");
    step(5).await;
    ed.close("other");
    step(1).await;
    Ok(())
}

//! Search Microsoft's stock content as the clip recorder's panels do.
//! usage: cargo run --example hubble_search -- <images|videos|stickers> [query] [sticker category]
use teams_cli::api::hubble::{EMOJI, STOCK_IMAGES, STOCK_VIDEOS, Search, search};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let pivot = match args.first().map(String::as_str) {
        Some("videos") => STOCK_VIDEOS,
        Some("stickers") => EMOJI,
        _ => STOCK_IMAGES,
    };
    let s = Search {
        query: args.get(1).cloned().unwrap_or_default(),
        pivot: pivot.into(),
        category: args.get(2).cloned(),
        page_size: 50,
        page_offset: 0,
    };
    let r = search(&[s], "en-us").await?;
    for it in &r[0] {
        println!("{} | {} | {} | {}", it.kind, it.name, it.url, it.thumb);
    }
    println!("{} items", r[0].len());
    Ok(())
}

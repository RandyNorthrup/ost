//! Add or remove a person in a group chat as Teams does (test aid, e.g.
//! the event group chat's "X and Y joined…" lines):
//! `cargo run --example chat_member -- add|remove <chat id> <object id>`.
use teams_cli::api::{client::TeamsClient, msgactions};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let mut args = std::env::args().skip(1);
    let op = args.next().expect("add or remove");
    let chat = args.next().expect("chat id");
    let oid = args.next().expect("object id");
    let mri = teams_cli::identity::user_mri(&oid);
    let client = TeamsClient::new().await?;
    match op.as_str() {
        "add" => {
            msgactions::add_chat_members(&client, &chat, &[mri], msgactions::SharedHistory::All)
                .await?
        }
        "remove" => msgactions::remove_chat_member(&client, &chat, &mri).await?,
        _ => anyhow::bail!("add or remove"),
    }
    println!("{op} done");
    Ok(())
}

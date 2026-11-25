//! Add someone to, or remove them from, a group chat (debugging aid):
//! `cargo run --example chat_members -- add|remove <chat id> <mri>`.
use teams_cli::api::client::TeamsClient;
use teams_cli::api::msgactions::{SharedHistory, add_chat_members, remove_chat_member};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let [op, chat, mri] = args.as_slice() else {
        anyhow::bail!("usage: chat_members add|remove <chat id> <mri>");
    };
    let client = TeamsClient::new().await?;
    match op.as_str() {
        "add" => {
            add_chat_members(
                &client,
                chat,
                std::slice::from_ref(mri),
                SharedHistory::None,
            )
            .await?
        }
        "remove" => remove_chat_member(&client, chat, mri).await?,
        _ => anyhow::bail!("add or remove"),
    }
    println!("{op} {mri}: done");
    Ok(())
}

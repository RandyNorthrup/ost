//! Start a group chat as the signed-in account (debugging aid; used for the
//! large-chat test rig): `cargo run --example group_chat_create -- "<topic>" <oid|mri>...`.
//! The signed-in account is added automatically.
use teams_cli::api::client::TeamsClient;
use teams_cli::api::create_group_chat;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let mut args = std::env::args().skip(1);
    let topic = args
        .next()
        .ok_or_else(|| anyhow::anyhow!("usage: group_chat_create <topic> <oid|mri>..."))?;
    let client = TeamsClient::new().await?;
    let me = client
        .self_mri()
        .ok_or_else(|| anyhow::anyhow!("not signed in"))?;
    let mut members = vec![me];
    for a in args {
        members.push(teams_cli::identity::user_mri(&a));
    }
    let id = create_group_chat(&client, &members, &topic).await?;
    println!("{} members: {id}", members.len());
    Ok(())
}

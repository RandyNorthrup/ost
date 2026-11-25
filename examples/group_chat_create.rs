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
    let me = format!(
        "8:orgid:{}",
        client
            .object_id()
            .ok_or_else(|| anyhow::anyhow!("not signed in"))?
    );
    let mut members = vec![me];
    for a in args {
        members.push(if a.starts_with("8:") {
            a
        } else {
            format!("8:orgid:{a}")
        });
    }
    let id = create_group_chat(&client, &members, &topic).await?;
    println!("{} members: {id}", members.len());
    Ok(())
}

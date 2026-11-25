//! Find the body Teams' provisioning service takes to accept a shared-channel
//! invite (debugging aid, TASK-0087): tries a few shapes in turn and stops at
//! the first that's accepted, printing each status and error text.
//! `OST_PROFILE=<invitee> cargo run --example invite_accept_probe -- <invitation id> <team thread>`
use teams_cli::api::client::TeamsClient;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let id = std::env::args().nth(1).expect("invitation id");
    let thread = std::env::args().nth(2).expect("team thread");
    let client = TeamsClient::new().await?;
    let base = client
        .region_endpoint("teamsAndChannelsProvisioningService")
        .expect("provisioning")
        .trim_end_matches('/')
        .to_string();
    let token =
        teams_cli::auth::oauth::access_token_for("https://templates.teams.microsoft.com/.default")
            .await?;
    let bodies = [
        serde_json::json!(thread),
        serde_json::json!({ "targetTeamThreadMri": thread }),
        serde_json::json!({ "teamThreadId": thread }),
        serde_json::json!({ "targetTeamThreadId": thread }),
        serde_json::json!({ "teamId": thread }),
    ];
    for b in bodies {
        let r = client
            .http()
            .post(format!("{base}/users/me/invitations/{id}/accept"))
            .bearer_auth(&token)
            .json(&b)
            .send()
            .await?;
        let st = r.status();
        let text = r.text().await.unwrap_or_default();
        println!(
            "{} -> {} {}",
            b,
            st,
            text.chars().take(400).collect::<String>()
        );
        if st.is_success() {
            break;
        }
    }
    Ok(())
}

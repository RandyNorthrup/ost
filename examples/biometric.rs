//! Teams' Recognition service (debugging aid):
//! `cargo run --example biometric -- status`
//! `cargo run --example biometric -- face-sign <photo.jpg>` (signature only, nothing stored)
//! `cargo run --example biometric -- face-enroll <photo.jpg>` (sign and store)
//! `cargo run --example biometric -- voice-enroll <16k-mono.wav> [--store]`
//! `cargo run --example biometric -- export voice|face <out.zip>`
//! `cargo run --example biometric -- remove-face | remove-voice | passive-off`
use teams_cli::api::biometric::{Biometric, FaceOutcome, HeadPose, VOICE_TEXT, face_signature, voice_signature};
use teams_cli::api::client::TeamsClient;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt().with_env_filter(tracing_subscriber::EnvFilter::from_default_env()).with_writer(std::io::stderr).init();
    let args: Vec<String> = std::env::args().skip(1).collect();
    let client = TeamsClient::new().await?;
    let bio = Biometric::new(&client).await?;
    match args.first().map(String::as_str) {
        Some("status") => println!("{:?}", bio.status().await?),
        Some(op @ ("face-sign" | "face-enroll")) => {
            let jpeg = std::fs::read(&args[1])?;
            let token = bio.cognition_token("face").await?;
            let oid = client.object_id().unwrap_or_default();
            let outcome = face_signature(client.http(), &token, &jpeg, HeadPose::Center, &oid, None).await?;
            match &outcome {
                FaceOutcome::Signed(s) => println!("signed: Type={} Version={} HeadPose={} Data={} chars", s["Type"], s["Version"], s["HeadPose"], s["Data"].as_str().map(str::len).unwrap_or(0)),
                FaceOutcome::Refused(r) => println!("refused: {r}"),
            }
            if let (FaceOutcome::Signed(s), "face-enroll") = (outcome, op) {
                bio.store_face(&[(jpeg, s)]).await?;
                println!("stored; status {:?}", bio.status().await?);
            }
        }
        Some("voice-enroll") => {
            let wav = std::fs::read(&args[1])?;
            let token = bio.cognition_token("voice").await?;
            let outcome = voice_signature(&token, "en-us", &wav, VOICE_TEXT, 25.0).await?;
            println!("{outcome:?}");
            if let (teams_cli::api::biometric::VoiceOutcome::Signed(s), true) = (&outcome, args.iter().any(|a| a == "--store")) {
                bio.store_voice("en-us", &wav, s).await?;
                println!("stored; status {:?}", bio.status().await?);
            }
        }
        Some("export") => {
            // `export voice|face <out>`: the profile's data as the service
            // exports it (Recognition's Export).
            let data = bio.export(&args[1]).await?;
            std::fs::write(&args[2], &data)?;
            println!("{} bytes", data.len());
        }
        Some("remove-face") => { bio.remove_face().await?; println!("removed; status {:?}", bio.status().await?) }
        Some("remove-voice") => { bio.remove_voice().await?; println!("removed; status {:?}", bio.status().await?) }
        Some("passive-off") => { bio.set_passive_voice(&client, false).await?; println!("opted out; {:?} {:?}", teams_cli::api::biometric::passive(&client).await?, bio.status().await?) }
        _ => anyhow::bail!("see the doc comment"),
    }
    Ok(())
}

//! Meeting Recaps' list day by day (debugging aid): `cargo run --example
//! recap_days -- [region] [days]` prints, for each local day back from
//! today, the rows Home and Generate audio recap get (subject, event id,
//! times, task and mention counts) and the day's catch-up recommendations
//! as the service gave them (subject, times, whether it has a calendar
//! event, counts).
#[tokio::main]
async fn main() -> anyhow::Result<()> {
    use chrono::{Local, TimeZone};
    let args: Vec<String> = std::env::args().skip(1).collect();
    let region = args.first().cloned().unwrap_or_else(|| "us".into());
    let days: i64 = args.get(1).and_then(|d| d.parse().ok()).unwrap_or(31);
    let today = Local::now().date_naive();
    let f = |t: chrono::DateTime<chrono::Utc>| t.to_rfc3339_opts(chrono::SecondsFormat::Millis, true);
    for i in 0..days {
        let day = today - chrono::Duration::days(i);
        let (Some(a), Some(b)) = (
            Local.from_local_datetime(&day.and_hms_opt(0, 0, 0).unwrap_or_default()).single(),
            Local.from_local_datetime(&day.and_hms_milli_opt(23, 59, 59, 999).unwrap_or_default()).single(),
        ) else {
            continue;
        };
        let rows = teams_cli::api::recaps::meetings(&region, i, 1).await?;
        let recs = teams_cli::api::recaps::catch_up_range(&f(a.with_timezone(&chrono::Utc)), &f(b.with_timezone(&chrono::Utc))).await;
        println!("== {day}");
        // RECAP_RAW=1: each thread's resources (type, the fields it has).
        if std::env::var_os("RECAP_RAW").is_some() {
            let v = teams_cli::api::recaps::day_contents(&region, a.with_timezone(&chrono::Utc), b.with_timezone(&chrono::Utc)).await?;
            for t in v["value"].as_array().into_iter().flatten() {
                println!("  raw  {} | event {}", t["threadInfo"]["subject"].as_str().unwrap_or_default(), !t["threadInfo"]["eventId"].as_str().unwrap_or_default().is_empty());
                for res in t["resources"].as_array().into_iter().flatten() {
                    let keys = |o: &serde_json::Value| o.as_object().map(|m| m.keys().cloned().collect::<Vec<_>>().join(",")).unwrap_or_default();
                    let kind = |v: &serde_json::Value| match v { serde_json::Value::String(s) => format!("str({})", s.len()), serde_json::Value::Null => "null".into(), o => o.to_string().chars().take(20).collect() };
                    println!("       {} | {} | metadata {} | id {} location {}", res["type"].as_str().unwrap_or_default(), keys(res), keys(&res["metadata"]), kind(&res["id"]), kind(&res["location"]));
                }
            }
        }
        for d in rows["days"].as_array().into_iter().flatten() {
            for m in d["meetings"].as_array().into_iter().flatten() {
                println!(
                    "  row  {} | event {} | {} - {} | tasks {} mentions {} | transcript {}",
                    m["subject"].as_str().unwrap_or_default(),
                    !m["eventId"].as_str().unwrap_or_default().is_empty(),
                    m["start"].as_str().unwrap_or_default(),
                    m["end"].as_str().unwrap_or_default(),
                    m["actionItemCount"],
                    m["mentionEventCount"],
                    m["transcript"]
                );
                // Home's row (TASK-0252): who spoke, the files, the
                // thumbnail's recording, whether you may open it.
                println!(
                    "       speakers {:?} | files {:?} | thumb {} | access {} | reasons {}",
                    m["speakers"].as_array().into_iter().flatten().map(|p| p["displayName"].as_str().unwrap_or_default()).collect::<Vec<_>>(),
                    m["files"].as_array().into_iter().flatten().map(|f| f["type"].as_str().unwrap_or_default()).collect::<Vec<_>>(),
                    !m["thumb"].is_null(),
                    m["access"].as_str().unwrap_or_default(),
                    m["reasons"]
                );
            }
        }
        match recs {
            Ok(v) => {
                for r in v.pointer("/EntitySets/0/ResultSets/0/Results").and_then(|r| r.as_array()).into_iter().flatten() {
                    let s = &r["Source"];
                    let n = |k: &str| s.pointer(&format!("/PointsOfInterest/{k}")).and_then(|x| x.as_array()).map(Vec::len).unwrap_or(0);
                    println!(
                        "  reco {} | event {} | {} - {} | tasks {} mentions {}",
                        s["MeetingSubject"].as_str().unwrap_or_default(),
                        !s["MeetingId"].as_str().unwrap_or_default().is_empty(),
                        s["MeetingStartTime"].as_str().unwrap_or_default(),
                        s["MeetingEndTime"].as_str().unwrap_or_default(),
                        n("ActionItems"),
                        n("MentionEvents")
                    );
                }
            }
            Err(e) => println!("  reco error {e}"),
        }
    }
    Ok(())
}

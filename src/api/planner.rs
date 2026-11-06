//! Tasks for the Planner app, as Teams' Planner (Tasks by Planner and
//! To Do) shows them: your private tasks (Microsoft To Do's default list)
//! and the Planner tasks assigned to you, plus your plans and their
//! tasks. Ids that go into Graph paths are checked first.

use std::collections::HashMap;

use anyhow::{Context, Result, bail};
use serde::{Deserialize, Serialize};

use super::client::TeamsClient;

/// One task.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct Task {
    pub id: String,
    pub title: String,
    /// "todo" (a private task) or "planner".
    pub kind: String,
    /// Where it lives: "Private tasks", or the plan's name.
    pub source: String,
    /// The To Do list or the plan it's in.
    pub container_id: String,
    /// The plan's bucket (Planner tasks).
    pub bucket: String,
    /// Due date, `YYYY-MM-DD` (empty when none).
    pub due: String,
    /// "Urgent", "Important", "Medium" or "Low".
    pub priority: String,
    pub completed: bool,
    /// Planner's ETag, needed to change a Planner task.
    #[serde(default)]
    pub etag: String,
}

/// A plan.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Plan {
    pub id: String,
    pub title: String,
    /// The team (group) that owns it, if any.
    pub group_id: String,
    pub team: String,
}

/// Graph ids: letters, digits and `-_=` only.
fn check_id(id: &str) -> Result<&str> {
    if id.is_empty()
        || id.len() > 300
        || !id
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"-_=".contains(&b))
    {
        bail!("Not a task id");
    }
    Ok(id)
}

fn s(v: &serde_json::Value, p: &str) -> String {
    v.pointer(p)
        .and_then(|x| x.as_str())
        .unwrap_or_default()
        .to_string()
}

/// Planner's 0–10 priority as Teams names it.
fn planner_priority(p: u64) -> &'static str {
    match p {
        0 | 1 => "Urgent",
        2..=4 => "Important",
        5..=7 => "Medium",
        _ => "Low",
    }
}

fn todo_task(v: &serde_json::Value, list_id: &str) -> Option<Task> {
    let id = s(v, "/id");
    if id.is_empty() {
        return None;
    }
    Some(Task {
        id,
        title: s(v, "/title"),
        kind: "todo".into(),
        source: "Private tasks".into(),
        container_id: list_id.to_string(),
        bucket: String::new(),
        due: s(v, "/dueDateTime/dateTime").chars().take(10).collect(),
        priority: match s(v, "/importance").as_str() {
            "high" => "Important",
            "low" => "Low",
            _ => "Medium",
        }
        .into(),
        completed: s(v, "/status") == "completed",
        etag: String::new(),
    })
}

fn planner_task(
    v: &serde_json::Value,
    plans: &HashMap<String, String>,
    buckets: &HashMap<String, String>,
) -> Option<Task> {
    let id = s(v, "/id");
    if id.is_empty() {
        return None;
    }
    let plan = s(v, "/planId");
    Some(Task {
        id,
        title: s(v, "/title"),
        kind: "planner".into(),
        source: plans.get(&plan).cloned().unwrap_or_else(|| "Plan".into()),
        container_id: plan,
        bucket: buckets.get(&s(v, "/bucketId")).cloned().unwrap_or_default(),
        due: s(v, "/dueDateTime").chars().take(10).collect(),
        priority: planner_priority(v.get("priority").and_then(|p| p.as_u64()).unwrap_or(5)).into(),
        completed: v.get("percentComplete").and_then(|p| p.as_u64()) == Some(100),
        etag: s(v, "/@odata.etag"),
    })
}

async fn json(client: &TeamsClient, path: &str) -> Result<serde_json::Value> {
    client
        .graph_get(path)
        .await?
        .json()
        .await
        .context("Planner reply")
}

/// Your To Do default list (where Teams' private tasks go).
async fn default_list(client: &TeamsClient) -> Result<String> {
    let v = json(client, "/me/todo/lists").await?;
    v["value"]
        .as_array()
        .into_iter()
        .flatten()
        .find(|l| l["wellknownListName"] == "defaultList")
        .or_else(|| v["value"].as_array().and_then(|a| a.first()))
        .and_then(|l| l["id"].as_str())
        .map(str::to_string)
        .context("No task list")
}

async fn plan_titles(
    client: &TeamsClient,
    ids: impl Iterator<Item = String>,
) -> HashMap<String, String> {
    let mut out = HashMap::new();
    for id in ids.take(40) {
        if out.contains_key(&id) || check_id(&id).is_err() {
            continue;
        }
        if let Ok(v) = json(client, &format!("/planner/plans/{id}?$select=id,title")).await {
            out.insert(id.clone(), s(&v, "/title"));
        }
    }
    out
}

/// My tasks: open private tasks and the Planner tasks assigned to you.
pub async fn my_tasks(client: &TeamsClient) -> Result<Vec<Task>> {
    let list = default_list(client).await?;
    let todo = json(
        client,
        &format!("/me/todo/lists/{}/tasks?$top=100", check_id(&list)?),
    )
    .await?;
    let mut tasks: Vec<Task> = todo["value"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|t| todo_task(t, &list))
        .filter(|t| !t.completed)
        .collect();
    let planner = json(client, "/me/planner/tasks?$top=100").await?;
    let items: Vec<&serde_json::Value> =
        planner["value"].as_array().into_iter().flatten().collect();
    let titles = plan_titles(client, items.iter().map(|t| s(t, "/planId"))).await;
    tasks.extend(
        items
            .into_iter()
            .filter_map(|t| planner_task(t, &titles, &HashMap::new()))
            .filter(|t| !t.completed),
    );
    // Flagged emails are best-effort (a mailbox may be unavailable).
    match flagged_emails(client).await {
        Ok(mut m) => tasks.append(&mut m),
        Err(e) => tracing::info!("flagged emails: {e:#}"),
    }
    Ok(tasks)
}

/// Your flagged emails, as Planner lists them (Source "Flagged email").
pub async fn flagged_emails(client: &TeamsClient) -> Result<Vec<Task>> {
    let v = json(
        client,
        "/me/messages?$filter=flag/flagStatus%20eq%20'flagged'&$select=id,subject,importance,flag&$top=50",
    )
    .await?;
    Ok(v["value"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|m| {
            let id = s(m, "/id");
            (!id.is_empty()).then(|| Task {
                id,
                title: {
                    let t = s(m, "/subject");
                    if t.is_empty() {
                        "(No subject)".into()
                    } else {
                        t
                    }
                },
                kind: "mail".into(),
                source: "Flagged email".into(),
                container_id: String::new(),
                bucket: String::new(),
                due: s(m, "/flag/dueDateTime/dateTime")
                    .chars()
                    .take(10)
                    .collect(),
                priority: if s(m, "/importance") == "high" {
                    "Important"
                } else {
                    "Medium"
                }
                .into(),
                completed: false,
                etag: String::new(),
            })
        })
        .collect())
}

/// Add a private task (To Do's default list), as "Add new task" does.
pub async fn add_private_task(client: &TeamsClient, title: &str, due: &str) -> Result<Task> {
    let title = title.trim();
    if title.is_empty() {
        bail!("A task needs a name");
    }
    let list = default_list(client).await?;
    let mut body = serde_json::json!({ "title": title });
    if !due.is_empty() {
        if due.len() != 10 || !due.bytes().all(|b| b.is_ascii_digit() || b == b'-') {
            bail!("Not a date: {due}");
        }
        body["dueDateTime"] =
            serde_json::json!({ "dateTime": format!("{due}T00:00:00"), "timeZone": "UTC" });
    }
    let v: serde_json::Value = client
        .graph_post(&format!("/me/todo/lists/{}/tasks", check_id(&list)?), &body)
        .await?
        .json()
        .await?;
    todo_task(&v, &list).context("New task reply had no task")
}

/// Mark a task complete.
pub async fn complete(client: &TeamsClient, task: &Task) -> Result<()> {
    match task.kind.as_str() {
        "todo" => {
            client
                .graph_patch(
                    &format!(
                        "/me/todo/lists/{}/tasks/{}",
                        check_id(&task.container_id)?,
                        check_id(&task.id)?
                    ),
                    &serde_json::json!({ "status": "completed" }),
                )
                .await?;
        }
        "mail" => {
            client
                .graph_patch(
                    &format!("/me/messages/{}", check_id(&task.id)?),
                    &serde_json::json!({ "flag": { "flagStatus": "complete" } }),
                )
                .await?;
        }
        "planner" => {
            if task.etag.is_empty() || task.etag.contains(['\r', '\n']) {
                bail!("Missing task version");
            }
            client
                .graph_change_with(
                    &format!("/planner/tasks/{}", check_id(&task.id)?),
                    Some(&serde_json::json!({ "percentComplete": 100 })),
                    &[("If-Match", task.etag.as_str())],
                )
                .await?;
        }
        _ => bail!("Unknown task"),
    }
    Ok(())
}

/// Delete a private task (cleaning up after a test, or the task menu).
pub async fn delete_private_task(client: &TeamsClient, task: &Task) -> Result<()> {
    if task.kind != "todo" {
        bail!("Only private tasks can be deleted here");
    }
    client
        .graph_delete(&format!(
            "/me/todo/lists/{}/tasks/{}",
            check_id(&task.container_id)?,
            check_id(&task.id)?
        ))
        .await?;
    Ok(())
}

/// Your plans: those of your teams.
pub async fn plans(client: &TeamsClient) -> Result<Vec<Plan>> {
    let mut out: Vec<Plan> = Vec::new();
    for team in super::list_teams_data(client).await?.into_iter().take(50) {
        if !team.id.bytes().all(|b| b.is_ascii_hexdigit() || b == b'-') {
            continue;
        }
        let Ok(v) = json(
            client,
            &format!("/groups/{}/planner/plans?$select=id,title", team.id),
        )
        .await
        else {
            continue;
        };
        for p in v["value"].as_array().into_iter().flatten() {
            let id = s(p, "/id");
            if !id.is_empty() && !out.iter().any(|x| x.id == id) {
                out.push(Plan {
                    id,
                    title: s(p, "/title"),
                    group_id: team.id.clone(),
                    team: team.name.clone(),
                });
            }
        }
    }
    Ok(out)
}

/// Create a plan in a team (plans belong to a team's group), as Teams'
/// Create a plan does; it gets a "To do" bucket to start with.
pub async fn create_plan(
    client: &TeamsClient,
    group_id: &str,
    team: &str,
    title: &str,
) -> Result<Plan> {
    let title = title.trim();
    if title.is_empty() {
        bail!("A plan needs a name");
    }
    if group_id.is_empty() || !group_id.bytes().all(|b| b.is_ascii_hexdigit() || b == b'-') {
        bail!("Not a team");
    }
    let body = serde_json::json!({
        "container": { "url": format!("https://graph.microsoft.com/v1.0/groups/{group_id}") },
        "title": title
    });
    let v: serde_json::Value = client
        .graph_post("/planner/plans", &body)
        .await?
        .json()
        .await?;
    let id = s(&v, "/id");
    check_id(&id)?;
    let bucket = serde_json::json!({ "name": "To do", "planId": id, "orderHint": " !" });
    if let Err(e) = client.graph_post("/planner/buckets", &bucket).await {
        tracing::info!("first bucket: {e:#}");
    }
    Ok(Plan {
        id,
        title: s(&v, "/title"),
        group_id: group_id.to_string(),
        team: team.to_string(),
    })
}

/// Delete a plan (needs its current ETag; used to clean up after tests).
pub async fn delete_plan(client: &TeamsClient, plan_id: &str) -> Result<()> {
    let id = check_id(plan_id)?;
    let v = json(client, &format!("/planner/plans/{id}")).await?;
    let etag = s(&v, "/@odata.etag");
    if etag.is_empty() || etag.contains(['\r', '\n']) {
        bail!("Missing plan version");
    }
    client
        .graph_change_with(
            &format!("/planner/plans/{id}"),
            None,
            &[("If-Match", etag.as_str())],
        )
        .await?;
    Ok(())
}

/// Add a task to a plan's first bucket.
pub async fn add_plan_task(client: &TeamsClient, plan: &Plan, title: &str) -> Result<()> {
    let title = title.trim();
    if title.is_empty() {
        bail!("A task needs a name");
    }
    let id = check_id(&plan.id)?;
    let buckets = json(client, &format!("/planner/plans/{id}/buckets?$select=id")).await?;
    let mut body = serde_json::json!({ "planId": id, "title": title });
    if let Some(b) = buckets["value"]
        .as_array()
        .and_then(|a| a.first())
        .and_then(|b| b["id"].as_str())
    {
        body["bucketId"] = serde_json::json!(b);
    }
    client.graph_post("/planner/tasks", &body).await?;
    Ok(())
}

/// A plan's open tasks, with their buckets.
pub async fn plan_tasks(client: &TeamsClient, plan: &Plan) -> Result<Vec<Task>> {
    let id = check_id(&plan.id)?;
    let buckets: HashMap<String, String> = json(
        client,
        &format!("/planner/plans/{id}/buckets?$select=id,name"),
    )
    .await?["value"]
        .as_array()
        .into_iter()
        .flatten()
        .map(|b| (s(b, "/id"), s(b, "/name")))
        .collect();
    let titles = HashMap::from([(plan.id.clone(), plan.title.clone())]);
    Ok(
        json(client, &format!("/planner/plans/{id}/tasks")).await?["value"]
            .as_array()
            .into_iter()
            .flatten()
            .filter_map(|t| planner_task(t, &titles, &buckets))
            .filter(|t| !t.completed)
            .collect(),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tasks_parse_from_todo_and_planner() {
        let t = todo_task(
            &serde_json::json!({ "id": "AAA=", "title": "Write docs", "importance": "high", "status": "notStarted",
                                 "dueDateTime": { "dateTime": "2026-11-09T00:00:00.0000000", "timeZone": "UTC" } }),
            "LIST",
        )
        .unwrap();
        assert_eq!(
            (t.source.as_str(), t.priority.as_str(), t.due.as_str()),
            ("Private tasks", "Important", "2026-11-09")
        );
        let plans = HashMap::from([("P1".to_string(), "Launch".to_string())]);
        let buckets = HashMap::from([("B1".to_string(), "To do".to_string())]);
        let p = planner_task(
            &serde_json::json!({ "id": "T1", "title": "Ship", "planId": "P1", "bucketId": "B1", "priority": 1,
                                 "percentComplete": 0, "@odata.etag": "W/\"x\"" }),
            &plans,
            &buckets,
        )
        .unwrap();
        assert_eq!(
            (
                p.source.as_str(),
                p.bucket.as_str(),
                p.priority.as_str(),
                p.completed
            ),
            ("Launch", "To do", "Urgent", false)
        );
        assert_eq!(planner_priority(9), "Low");
        assert!(check_id("../x").is_err());
    }
}

//! OneNote for the OneNote app: your notebooks, their sections and pages,
//! a page's content, and new pages. Ids that go into Graph paths are
//! checked first; page HTML is reduced to what a rich-text view shows.

use anyhow::{Result, bail};
use serde::Serialize;

use super::client::TeamsClient;

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Notebook {
    pub id: String,
    pub name: String,
    pub modified: String,
    /// OneNote on the web.
    pub web_url: String,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Section {
    pub id: String,
    pub name: String,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Page {
    pub id: String,
    pub title: String,
    pub modified: String,
    pub web_url: String,
}

/// OneNote ids look like `1-abc...!123` or `0-...`: letters, digits and
/// `-`, `!`, `_`, `.`.
fn check_id(id: &str) -> Result<&str> {
    if id.is_empty()
        || id.len() > 400
        || !id
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b"-!_.".contains(&b))
    {
        bail!("Not a OneNote id");
    }
    Ok(id)
}

fn s(v: &serde_json::Value, p: &str) -> String {
    v.pointer(p)
        .and_then(|x| x.as_str())
        .unwrap_or_default()
        .to_string()
}

async fn values(client: &TeamsClient, path: &str) -> Result<Vec<serde_json::Value>> {
    let v: serde_json::Value = client.graph_get(path).await?.json().await?;
    Ok(v.get("value")
        .and_then(|x| x.as_array())
        .cloned()
        .unwrap_or_default())
}

/// Your notebooks, most recently changed first. (OneNote answers 403
/// to $select / $orderby here, so the list is sorted locally.)
pub async fn notebooks(client: &TeamsClient) -> Result<Vec<Notebook>> {
    let mut list: Vec<Notebook> = values(client, "/me/onenote/notebooks")
        .await?
        .iter()
        .filter(|n| !s(n, "/id").is_empty())
        .map(|n| Notebook {
            id: s(n, "/id"),
            name: s(n, "/displayName"),
            modified: s(n, "/lastModifiedDateTime"),
            web_url: s(n, "/links/oneNoteWebUrl/href"),
        })
        .collect();
    list.sort_by(|a, b| b.modified.cmp(&a.modified));
    Ok(list)
}

/// A notebook's sections.
pub async fn sections(client: &TeamsClient, notebook_id: &str) -> Result<Vec<Section>> {
    let id = check_id(notebook_id)?;
    Ok(
        values(client, &format!("/me/onenote/notebooks/{id}/sections"))
            .await?
            .iter()
            .filter(|x| !s(x, "/id").is_empty())
            .map(|x| Section {
                id: s(x, "/id"),
                name: s(x, "/displayName"),
            })
            .collect(),
    )
}

/// A section's pages, most recently changed first.
pub async fn pages(client: &TeamsClient, section_id: &str) -> Result<Vec<Page>> {
    let id = check_id(section_id)?;
    Ok(
        values(client, &format!("/me/onenote/sections/{id}/pages?$top=100"))
            .await?
            .iter()
            .filter(|x| !s(x, "/id").is_empty())
            .map(|x| Page {
                id: s(x, "/id"),
                title: {
                    let t = s(x, "/title");
                    if t.is_empty() {
                        "Untitled page".into()
                    } else {
                        t
                    }
                },
                modified: s(x, "/lastModifiedDateTime"),
                web_url: s(x, "/links/oneNoteWebUrl/href"),
            })
            .collect::<Vec<_>>(),
    )
    .map(|mut v| {
        v.sort_by(|a: &Page, b: &Page| b.modified.cmp(&a.modified));
        v
    })
}

/// A page's content, as HTML a rich-text view can show: the body only,
/// without scripts, styles, objects or images (those need the page's own
/// authenticated resources).
pub async fn page_html(client: &TeamsClient, page_id: &str) -> Result<String> {
    let id = check_id(page_id)?;
    let html = client
        .graph_get(&format!("/me/onenote/pages/{id}/content"))
        .await?
        .text()
        .await?;
    Ok(rich_text(&html))
}

/// Reduce OneNote's page HTML to safe rich text.
pub fn rich_text(html: &str) -> String {
    let lower = html.to_ascii_lowercase();
    let body = match (lower.find("<body"), lower.rfind("</body>")) {
        (Some(a), Some(b)) if b > a => {
            let start = html[a..].find('>').map(|i| a + i + 1).unwrap_or(a);
            &html[start..b]
        }
        _ => html,
    };
    let mut out = body.to_string();
    for tag in ["script", "style", "object", "iframe"] {
        loop {
            let l = out.to_ascii_lowercase();
            let Some(a) = l.find(&format!("<{tag}")) else {
                break;
            };
            let end = l[a..]
                .find(&format!("</{tag}>"))
                .map(|i| a + i + tag.len() + 3)
                .unwrap_or(l.len());
            out.replace_range(a..end, "");
        }
    }
    // Images point at authenticated resources: show a marker instead.
    loop {
        let l = out.to_ascii_lowercase();
        let Some(a) = l.find("<img") else { break };
        let end = l[a..].find('>').map(|i| a + i + 1).unwrap_or(l.len());
        out.replace_range(a..end, "[image]");
    }
    // Positioned divs and inline styles carry absolute layout: drop the
    // style attributes so the text flows.
    while let Some(a) = out.to_ascii_lowercase().find(" style=\"") {
        let end = out[a + 8..]
            .find('"')
            .map(|i| a + 8 + i + 1)
            .unwrap_or(out.len());
        out.replace_range(a..end, "");
    }
    out
}

/// Create a notebook (with a first section, as OneNote starts one).
pub async fn create_notebook(client: &TeamsClient, name: &str) -> Result<Notebook> {
    let name = name.trim();
    // OneNote refuses these characters in names.
    if name.is_empty()
        || name.len() > 128
        || name.contains(['?', '*', '/', ':', '<', '>', '|', '\\', '"', '\''])
    {
        bail!("That isn't a notebook name OneNote takes");
    }
    let v: serde_json::Value = client
        .graph_post(
            "/me/onenote/notebooks",
            &serde_json::json!({ "displayName": name }),
        )
        .await?
        .json()
        .await?;
    let nb = Notebook {
        id: s(&v, "/id"),
        name: s(&v, "/displayName"),
        modified: s(&v, "/lastModifiedDateTime"),
        web_url: s(&v, "/links/oneNoteWebUrl/href"),
    };
    create_section(client, &nb.id, "Quick Notes").await?;
    Ok(nb)
}

/// Add a section to a notebook.
pub async fn create_section(
    client: &TeamsClient,
    notebook_id: &str,
    name: &str,
) -> Result<Section> {
    let id = check_id(notebook_id)?;
    let name = name.trim();
    if name.is_empty()
        || name.len() > 50
        || name.contains([
            '?', '*', '/', ':', '<', '>', '|', '\\', '"', '\'', '&', '#', '%', '~',
        ])
    {
        bail!("That isn't a section name OneNote takes");
    }
    let v: serde_json::Value = client
        .graph_post(
            &format!("/me/onenote/notebooks/{id}/sections"),
            &serde_json::json!({ "displayName": name }),
        )
        .await?
        .json()
        .await?;
    Ok(Section {
        id: s(&v, "/id"),
        name: s(&v, "/displayName"),
    })
}

/// Add a page to a section: a title and plain text paragraphs.
pub async fn create_page(
    client: &TeamsClient,
    section_id: &str,
    title: &str,
    text: &str,
) -> Result<Page> {
    let id = check_id(section_id)?;
    let esc = |t: &str| {
        t.replace('&', "&amp;")
            .replace('<', "&lt;")
            .replace('>', "&gt;")
            .replace('"', "&quot;")
    };
    let title = title.trim();
    if title.is_empty() {
        bail!("A page needs a title");
    }
    let body: String = text.lines().map(|l| format!("<p>{}</p>", esc(l))).collect();
    let html = format!(
        "<!DOCTYPE html><html><head><title>{}</title><meta name=\"created\" content=\"{}\" /></head><body>{}</body></html>",
        esc(title),
        chrono::Utc::now().format("%Y-%m-%dT%H:%M:%SZ"),
        body
    );
    let v: serde_json::Value = client
        .graph_post_raw(
            &format!("/me/onenote/sections/{id}/pages"),
            "application/xhtml+xml",
            html,
        )
        .await?
        .json()
        .await?;
    Ok(Page {
        id: s(&v, "/id"),
        title: s(&v, "/title"),
        modified: s(&v, "/lastModifiedDateTime"),
        web_url: s(&v, "/links/oneNoteWebUrl/href"),
    })
}

/// Delete a page (used to clean up after tests, and the page menu).
pub async fn delete_page(client: &TeamsClient, page_id: &str) -> Result<()> {
    let id = check_id(page_id)?;
    client
        .graph_delete(&format!("/me/onenote/pages/{id}"))
        .await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn page_html_is_reduced_to_rich_text() {
        let html = "<html><head><title>T</title><script>x()</script></head><body data-absolute-enabled=\"true\" style=\"font-family:Calibri\"><div style=\"position:absolute;left:48px\"><p>Hello <b>there</b></p><img src=\"https://graph/x\" /><script>evil()</script></div></body></html>";
        let r = rich_text(html);
        assert!(r.contains("<p>Hello <b>there</b></p>"));
        assert!(r.contains("[image]"));
        assert!(!r.contains("script") && !r.contains("evil") && !r.contains("position:absolute"));
        assert!(!r.contains("<title>"));
    }

    #[test]
    fn ids_are_checked() {
        assert!(check_id("1-f7a1b2c3!45").is_ok());
        assert!(check_id("../x").is_err());
        assert!(check_id("a?b").is_err());
    }
}

//! OST's Help (F1): the articles in docs/help, as Teams' Help shows
//! Microsoft's (docs/spec/feedback-and-help.md §4). Each category folder
//! has an `index.md` (its name and description); each article starts with
//! `title`, `description` and optionally `featured: true`.

/// Teams' nine Browse all help categories, in its order.
pub const CATEGORIES: [&str; 9] = [
    "get-started",
    "chat",
    "meetings",
    "teams-and-channels",
    "notifications-and-settings",
    "calls-and-devices",
    "files",
    "apps-and-services",
    "troubleshoot",
];

#[derive(Debug, Clone, Default, serde::Serialize)]
pub struct Article {
    /// "chat/find-in-a-chat".
    pub id: String,
    pub category: String,
    pub title: String,
    pub description: String,
    pub featured: bool,
    /// The Markdown after the front matter.
    pub body: String,
}

#[derive(Debug, Clone, Default, serde::Serialize)]
pub struct Category {
    pub id: String,
    pub title: String,
    pub description: String,
    pub articles: Vec<Article>,
}

/// The front matter's fields and the rest.
fn front_matter(text: &str) -> (Vec<(String, String)>, String) {
    let Some(rest) = text.strip_prefix("---\n") else { return (Vec::new(), text.to_string()) };
    let Some(end) = rest.find("\n---") else { return (Vec::new(), text.to_string()) };
    let fields = rest[..end]
        .lines()
        .filter_map(|l| l.split_once(':'))
        .map(|(k, v)| (k.trim().to_string(), v.trim().to_string()))
        .collect();
    let body = rest[end + 4..].trim_start_matches('\n').to_string();
    (fields, body)
}

fn field(fields: &[(String, String)], key: &str) -> String {
    fields.iter().find(|(k, _)| k == key).map(|(_, v)| v.clone()).unwrap_or_default()
}

/// The categories with their articles from `files` ([(path under
/// docs/help, text)]), in Teams' order; articles by title.
pub fn library(files: &[(&str, &str)]) -> Vec<Category> {
    let mut cats: Vec<Category> = CATEGORIES.iter().map(|c| Category { id: c.to_string(), ..Default::default() }).collect();
    for (path, text) in files {
        let Some((cat, file)) = path.split_once('/') else { continue };
        let Some(c) = cats.iter_mut().find(|c| c.id == cat) else { continue };
        let (fields, body) = front_matter(text);
        if file == "index.md" {
            c.title = field(&fields, "title");
            c.description = field(&fields, "description");
            continue;
        }
        let Some(slug) = file.strip_suffix(".md") else { continue };
        c.articles.push(Article {
            id: format!("{cat}/{slug}"),
            category: cat.to_string(),
            title: field(&fields, "title"),
            description: field(&fields, "description"),
            featured: field(&fields, "featured") == "true",
            body,
        });
    }
    for c in &mut cats {
        c.articles.sort_by(|a, b| a.title.cmp(&b.title));
    }
    cats
}

/// Articles matching `query`, best first: every word must appear; title
/// matches count most, then the description, then the text.
pub fn search(cats: &[Category], query: &str) -> Vec<Article> {
    let words: Vec<String> = query.split_whitespace().map(|w| w.to_lowercase()).collect();
    if words.is_empty() {
        return Vec::new();
    }
    let mut hits: Vec<(u32, Article)> = Vec::new();
    for a in cats.iter().flat_map(|c| &c.articles) {
        let (t, d, b) = (a.title.to_lowercase(), a.description.to_lowercase(), a.body.to_lowercase());
        let mut score = 0;
        let mut all = true;
        for w in &words {
            let s = 8 * u32::from(t.contains(w.as_str())) + 3 * u32::from(d.contains(w.as_str())) + u32::from(b.contains(w.as_str()));
            if s == 0 {
                all = false;
                break;
            }
            score += s;
        }
        if all {
            hits.push((score, a.clone()));
        }
    }
    hits.sort_by(|x, y| y.0.cmp(&x.0).then(x.1.title.cmp(&y.1.title)));
    hits.into_iter().map(|(_, a)| a).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    const FILES: [(&str, &str); 4] = [
        ("chat/index.md", "---\ntitle: Chat\ndescription: One-on-one, in a group, or with yourself.\n---\n"),
        ("chat/find-in-a-chat.md", "---\ntitle: Find something in a chat\ndescription: Search one chat.\nfeatured: true\n---\n\n# Find something in a chat\n\nPress Ctrl+F.\n"),
        ("chat/start-a-chat.md", "---\ntitle: Start a chat\ndescription: Chat with people.\n---\n\nSelect New message, then search for people.\n"),
        ("nowhere/x.md", "---\ntitle: X\n---\n"),
    ];

    #[test]
    fn articles_are_read_into_teams_categories() {
        let lib = library(&FILES);
        assert_eq!(lib.len(), 9);
        assert_eq!(lib[1].id, "chat");
        assert_eq!(lib[1].title, "Chat");
        assert_eq!(lib[1].description, "One-on-one, in a group, or with yourself.");
        assert_eq!(lib[1].articles.len(), 2);
        let f = &lib[1].articles[0];
        assert_eq!((f.id.as_str(), f.title.as_str(), f.featured), ("chat/find-in-a-chat", "Find something in a chat", true));
        assert!(f.body.starts_with("# Find something in a chat"));
    }

    #[test]
    fn search_ranks_titles_first_and_needs_every_word() {
        let lib = library(&FILES);
        let r = search(&lib, "people search");
        assert_eq!(r.iter().map(|a| a.title.as_str()).collect::<Vec<_>>(), ["Start a chat"], "only articles with both words");
        let r = search(&lib, "chat search");
        assert_eq!(r[0].title, "Find something in a chat", "title and description outrank the text");
        let r = search(&lib, "chat");
        assert_eq!(r[0].title, "Find something in a chat");
        assert!(search(&lib, "  ").is_empty());
    }
}

//! Where OST's tokens may go: the one check every request that attaches a
//! Teams, Skype, IC3 or Graph token makes on its exact destination.
//!
//! A token is attached only when the address is `https`, carries no user
//! name or password, names a host (not an IP address) and that host is one
//! of the Microsoft services the token is meant for: an exact host, or a
//! subdomain of a listed domain matched on a label boundary
//! (`x.teams.microsoft.com` matches `teams.microsoft.com`;
//! `evil-teams.microsoft.com.example` and `evilteams.microsoft.com` don't).
//! Everything else (card images, link previews and other third-party
//! addresses) is fetched without credentials, or not at all.

use anyhow::{Result, bail};

/// Which token a request carries.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Audience {
    /// The Skype token (and the IC3 token Teams' calling stack swaps in):
    /// Teams' chat, media store (AMS), URL preview proxy, call controller,
    /// presence and the other Teams services in the account's region
    /// endpoints (authsvc's `regionGtms`).
    Teams,
    /// Microsoft Graph.
    Graph,
}

/// Domains (with their subdomains) the Skype/IC3 tokens go to. Every
/// regional endpoint Teams' authsvc hands out is under one of them
/// (checked against the work tenant's `regionGtms`, 2026-11-25).
const TEAMS_DOMAINS: &[&str] = &[
    "teams.microsoft.com",
    "teams.cloud.microsoft",
    "teams.office.com",
    "teams.internal.office.com",
    "teams.core.microsoft",
    "teams.live.com",
    "skype.com",
    // Trouter, Teams' push channel (Skype's).
    "trouter.io",
];

/// Exact hosts the Skype token also goes to: the URL preview proxy's
/// picture host.
const TEAMS_HOSTS: &[&str] = &["urlp.sfbassets.com"];

const GRAPH_HOSTS: &[&str] = &["graph.microsoft.com"];

/// Microsoft's own service domains a token-bearing request may be
/// redirected to (the same services, their file stores and sign-in). Not
/// domains anyone can register a subdomain of (Azure's windows.net,
/// azurewebsites.net, azureedge.net).
const MICROSOFT_DOMAINS: &[&str] = &[
    "microsoft.com",
    "office.com",
    "office.net",
    "office365.com",
    "officeapps.live.com",
    "sharepoint.com",
    "svc.ms",
    "1drv.com",
    "onenote.com",
    "microsoftonline.com",
    "live.com",
    "skype.com",
    "trouter.io",
    "sfbassets.com",
];

/// The address's host when it is a well-formed `https` address with a DNS
/// name and no credentials in it; lowercase, as `url` normalizes it.
fn https_host(url: &str) -> Option<String> {
    let u = url::Url::parse(url.trim()).ok()?;
    if u.scheme() != "https" || !u.username().is_empty() || u.password().is_some() {
        return None;
    }
    match u.host()? {
        url::Host::Domain(d) => {
            let d = d.to_ascii_lowercase();
            // A trailing dot names the same host to DNS but slips past an
            // exact comparison; nothing Teams uses has one.
            (!d.is_empty() && !d.ends_with('.')).then_some(d)
        }
        url::Host::Ipv4(_) | url::Host::Ipv6(_) => None,
    }
}

/// `host` is `domain` or one of its subdomains (label boundary).
fn under(host: &str, domain: &str) -> bool {
    host == domain
        || host
            .strip_suffix(domain)
            .is_some_and(|rest| rest.ends_with('.'))
}

/// A host under Microsoft's own top-level domain (`.microsoft`).
fn microsoft_tld(host: &str) -> bool {
    host.rsplit('.').next() == Some("microsoft") && host.contains('.')
}

/// Whether a request to `url` may carry a token for `audience`.
pub fn allowed(url: &str, audience: Audience) -> bool {
    let Some(host) = https_host(url) else {
        return false;
    };
    match audience {
        Audience::Teams => {
            TEAMS_DOMAINS.iter().any(|d| under(&host, d)) || TEAMS_HOSTS.contains(&host.as_str())
        }
        Audience::Graph => GRAPH_HOSTS.contains(&host.as_str()),
    }
}

/// [`allowed`], as an error naming only the host (never the address,
/// which can carry a query).
pub fn ensure(url: &str, audience: Audience) -> Result<()> {
    if allowed(url, audience) {
        return Ok(());
    }
    let host = url::Url::parse(url)
        .ok()
        .and_then(|u| u.host_str().map(str::to_string))
        .unwrap_or_default();
    bail!("Refusing to send credentials to {host:?}: not a Microsoft service address for them")
}

/// A token-bearing request's address, built so it can only be one of the
/// Microsoft services `audience`'s token is for: `base` (a regional
/// endpoint) must pass [`allowed`] (https, exact host allowlist), each of
/// `segments` is appended as one percent-encoded path segment (a value
/// can't add a path, query or host of its own), and `query` is encoded.
pub fn service_url(
    base: &str,
    audience: Audience,
    segments: &[&str],
    query: &[(&str, &str)],
) -> Result<reqwest::Url> {
    ensure(base, audience)?;
    let mut u = reqwest::Url::parse(base)?;
    {
        let mut path = u
            .path_segments_mut()
            .map_err(|_| anyhow::anyhow!("Not a service address"))?;
        path.pop_if_empty();
        for s in segments {
            path.push(s);
        }
    }
    if !query.is_empty() {
        u.query_pairs_mut().extend_pairs(query);
    }
    Ok(u)
}

/// Whether a request carrying a token may follow a redirect to `url`:
/// https, and one of the token hosts or Microsoft's own services.
pub fn redirect_allowed(url: &str) -> bool {
    let Some(host) = https_host(url) else {
        return false;
    };
    allowed(url, Audience::Teams)
        || allowed(url, Audience::Graph)
        || microsoft_tld(&host)
        || MICROSOFT_DOMAINS.iter().any(|d| under(&host, d))
}

/// The redirect policy for HTTP clients whose requests carry tokens.
/// reqwest drops `Authorization` and `Cookie` on a redirect to another
/// host, but not Teams' own headers (`X-Skypetoken`, `Authentication`), so
/// a redirect off Microsoft's services, or to plain http, is not followed.
pub fn redirect_policy() -> reqwest::redirect::Policy {
    reqwest::redirect::Policy::custom(|attempt| {
        if attempt.previous().len() >= 10 {
            attempt.error("too many redirects")
        } else if redirect_allowed(attempt.url().as_str()) {
            attempt.follow()
        } else {
            tracing::warn!(
                host = attempt.url().host_str().unwrap_or_default(),
                "not following a redirect off Microsoft's services"
            );
            attempt.stop()
        }
    })
}

/// An HTTP client for token-bearing requests (see [`redirect_policy`]).
pub fn http_client() -> reqwest::Client {
    reqwest::Client::builder()
        .redirect(redirect_policy())
        .build()
        .unwrap_or_else(|_| reqwest::Client::new())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn teams_services_get_the_teams_token() {
        for u in [
            "https://teams.microsoft.com/api/mt/part/amer-03/beta/users",
            "https://amer.ng.msg.teams.microsoft.com/v1/users/ME/conversations",
            "https://us-api.asm.skype.com/v1/objects/0-wus-d1-abc/views/imgo",
            "https://us-storage.asm.skype.com:444/v1/objects/x",
            "https://us-prod.asyncgw.teams.microsoft.com/urlp/v1/url/content?url=https%3a%2f%2fexample.com%2fa.png",
            "https://noam.msgapi.teams.microsoft.com:444/x",
            "https://csa.svcs.teams.office.com/x",
            "https://amer03.public.mt.teams.internal.office.com/x",
            "https://prod.appsuggestions.teams.cloud.microsoft/x",
            "https://us.antiphish.teams.core.microsoft/x",
            "https://api.flightproxy.teams.microsoft.com/api/v2/ep/x",
            "https://pub-ent-ussc-05-f.trouter.teams.microsoft.com/v4/f/x",
            "https://teams.live.com/api/chatsvc/consumer/v1/x",
            "https://urlp.sfbassets.com/x",
            "HTTPS://TEAMS.MICROSOFT.COM/x",
        ] {
            assert!(allowed(u, Audience::Teams), "{u}");
        }
        assert!(allowed(
            "https://graph.microsoft.com/v1.0/me",
            Audience::Graph
        ));
        assert!(!allowed(
            "https://graph.microsoft.com/v1.0/me",
            Audience::Teams
        ));
        assert!(!allowed("https://teams.microsoft.com/x", Audience::Graph));
    }

    #[test]
    fn lookalikes_and_other_addresses_get_nothing() {
        for u in [
            // Plain http, even to the right host.
            "http://us-prod.asyncgw.teams.microsoft.com/urlp/v1/url/content?url=x",
            "http://teams.microsoft.com/",
            // Lookalike hosts.
            "https://evil-microsoft.com/",
            "https://evilteams.microsoft.com.evil.net/",
            "https://teams.microsoft.com.evil.net/x",
            "https://microsoft.com.evil.net/",
            "https://evilskype.com/",
            "https://asm.skype.com.evil.example/x",
            "https://notteams.microsoft.com/",
            "https://teams.microsoft.com./x",
            // The host hidden behind user info, a fragment or a query.
            "https://teams.microsoft.com@evil.example/x",
            "https://user:pw@teams.microsoft.com/x",
            "https://evil.example#.teams.microsoft.com",
            "https://evil.example?.teams.microsoft.com",
            "https://evil.example/.teams.microsoft.com",
            "https://evil.example\\.teams.microsoft.com",
            // IP literals.
            "https://127.0.0.1/x",
            "https://10.0.0.1/x",
            "https://[::1]/x",
            "https://52.113.194.132/x",
            // Not https, or not an address.
            "ftp://teams.microsoft.com/x",
            "wss://go.trouter.teams.microsoft.com/x",
            "data:image/png;base64,AAAA",
            "teams.microsoft.com/x",
            "",
            // Third-party pictures.
            "https://media1.giphy.com/media/x/giphy.gif",
            "https://example.com/card.png",
        ] {
            assert!(!allowed(u, Audience::Teams), "{u}");
            assert!(!allowed(u, Audience::Graph), "{u}");
        }
        assert!(!allowed(
            "https://graph.microsoft.com.evil.net/",
            Audience::Graph
        ));
        assert!(!allowed(
            "https://evilgraph.microsoft.com/",
            Audience::Graph
        ));
        assert!(!allowed("https://x.graph.microsoft.com/", Audience::Graph));
        let e = ensure("https://evil.example/a?token=secret", Audience::Teams).unwrap_err();
        assert!(!e.to_string().contains("secret"), "{e}");
    }

    #[test]
    fn service_addresses_are_built_safely() {
        let u = service_url(
            "https://teams.microsoft.com/api/mt/part/amer-03",
            Audience::Teams,
            &[
                "v2.0",
                "me",
                "calendars",
                "events",
                "040000008200e0",
                "respond",
            ],
            &[
                ("eventType", "Single"),
                ("eventStartDateTime", "2026-11-25T10:00:00.000Z"),
            ],
        )
        .unwrap();
        assert_eq!(
            u.as_str(),
            "https://teams.microsoft.com/api/mt/part/amer-03/v2.0/me/calendars/events/040000008200e0/respond?eventType=Single&eventStartDateTime=2026-11-25T10%3A00%3A00.000Z"
        );
        // A value stays one segment.
        let u = service_url(
            "https://teams.microsoft.com/api/x/",
            Audience::Teams,
            &["a/../../b?c#d"],
            &[],
        )
        .unwrap();
        assert_eq!(
            u.as_str(),
            "https://teams.microsoft.com/api/x/a%2F..%2F..%2Fb%3Fc%23d"
        );
        assert!(
            service_url(
                "http://teams.microsoft.com/api",
                Audience::Teams,
                &["x"],
                &[]
            )
            .is_err()
        );
        assert!(service_url("https://evil.example/api", Audience::Teams, &["x"], &[]).is_err());
    }

    #[test]
    fn redirects_stay_on_microsofts_services_over_https() {
        assert!(redirect_allowed("https://contoso.sharepoint.com/x"));
        assert!(redirect_allowed("https://loop.cloud.microsoft/x"));
        assert!(redirect_allowed("https://login.microsoftonline.com/x"));
        assert!(redirect_allowed("https://us-api.asm.skype.com/x"));
        assert!(!redirect_allowed("http://contoso.sharepoint.com/x"));
        assert!(!redirect_allowed("https://evil.example/x"));
        assert!(!redirect_allowed("https://x.blob.core.windows.net/x"));
        assert!(!redirect_allowed("https://microsoft.evil.example/x"));
        assert!(!redirect_allowed("https://evilmicrosoft.com/x"));
        assert!(!redirect_allowed("https://10.0.0.1/x"));
    }
}

//! An emulated Teams phone for Better Together (TASK-0162): it does what a
//! Teams phone signed in as the same user does toward the user's desktops,
//! over the same transport (`api::better_together`).
//!
//! - Connects its own Trouter socket and registers its Better Together
//!   endpoint (the socket's `bettertogether` path).
//! - Advertises the phone's Bluetooth LE beacon (Microsoft's `34 F0 40`,
//!   the user's object id, its salt and endpoint signature) through
//!   `bluetoothctl` on the chosen controller, so desktops nearby find it.
//! - `pair`: finds the user's desktops at the registrar, sends each a
//!   `broadcast`, takes the first that answers (or `--desktop=<endpoint
//!   id>`), sends it `pair` and waits for the user's answer there.
//! - Then answers the desktop's `keepalive`, `lock`, `unlock` and
//!   `unpair` with Teams' `response`, and reports an unpair.
//!
//! usage: OST_PROFILE=<profile> cargo run --example teams_phone --
//!   [pair|listen] [--name=<device name>] [--controller=<MAC>]
//!   [--salt=<n>] [--signature=<n>] [--wired] [--desktop=<endpoint id>]
//!   [--minutes=<n>]
use std::time::Duration;

use anyhow::{Context, Result, bail};
use teams_cli::api::better_together::{self as bt, Endpoint, Message, command};
use teams_cli::api::client::TeamsClient;
use teams_cli::event_hub::{self, EventKind};

struct Opts {
    pair: bool,
    name: String,
    controller: Option<String>,
    salt: u16,
    signature: i16,
    wired: bool,
    desktop: Option<String>,
    minutes: u64,
}

fn opts() -> Opts {
    let mut o = Opts {
        pair: false,
        name: "OST TEST 162 Phone".into(),
        controller: None,
        salt: 0x1620,
        signature: 162,
        wired: false,
        desktop: None,
        minutes: 30,
    };
    for a in std::env::args().skip(1) {
        let (k, v) = a.split_once('=').unwrap_or((a.as_str(), ""));
        match k {
            "pair" => o.pair = true,
            "listen" => o.pair = false,
            "--name" => o.name = v.into(),
            "--controller" => o.controller = Some(v.into()),
            "--salt" => o.salt = v.parse().unwrap_or(o.salt),
            "--signature" => o.signature = v.parse().unwrap_or(o.signature),
            "--wired" => o.wired = true,
            "--desktop" => o.desktop = Some(v.into()),
            "--minutes" => o.minutes = v.parse().unwrap_or(o.minutes),
            _ => eprintln!("unknown argument {a}"),
        }
    }
    o
}

/// The phone's beacon, advertised by bluetoothctl until the phone stops.
fn advertise(o: &Opts, oid: &str) -> Result<std::process::Child> {
    use std::io::Write;
    let data = bt::companion_beacon(oid, o.salt, o.signature).context("the user's object id isn't a GUID")?;
    let bytes: Vec<String> = data.iter().map(|b| format!("0x{b:02x}")).collect();
    let mut child = std::process::Command::new("bluetoothctl")
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::null())
        .spawn()
        .context("bluetoothctl")?;
    let mut script = String::new();
    if let Some(c) = &o.controller {
        script.push_str(&format!("select {c}\npower on\n"));
    }
    script.push_str(&format!("menu advertise\nmanufacturer 0x0006 {}\nback\nadvertise broadcast\n", bytes.join(" ")));
    child.stdin.as_mut().context("bluetoothctl stdin")?.write_all(script.as_bytes())?;
    println!("beacon: {}", data.iter().map(|b| format!("{b:02x}")).collect::<Vec<_>>().join(" "));
    Ok(child)
}

fn stop_advertising(mut child: std::process::Child) {
    use std::io::Write;
    if let Some(stdin) = child.stdin.as_mut() {
        let _ = stdin.write_all(b"advertise off\nquit\n");
    }
    std::thread::sleep(Duration::from_millis(500));
    let _ = child.kill();
    let _ = child.wait();
}

struct Phone {
    http: reqwest::Client,
    token: String,
    me: Endpoint,
    seq: u64,
    details: serde_json::Value,
}

impl Phone {
    async fn send(&mut self, url: &str, cmd: &str, extra: serde_json::Value) -> Result<Message> {
        self.seq += 1;
        let mut details = self.details.clone();
        if let (Some(d), Some(e)) = (details.as_object_mut(), extra.as_object()) {
            for (k, v) in e {
                d.insert(k.clone(), v.clone());
            }
        }
        let msg = self.me.message(cmd, &details, self.seq);
        let (status, body) = bt::send(&self.http, &self.token, url, &msg).await?;
        println!("-> {cmd} to {url}: {status} {body}");
        Ok(msg)
    }

    async fn respond(&mut self, to: &Message, ok: bool, result: serde_json::Value) -> Result<()> {
        let url = to.transport_details.url.clone();
        if url.is_empty() {
            bail!("the {} command named no URL to answer", to.command);
        }
        self.seq += 1;
        let msg = self.me.message(command::RESPONSE, &bt::response_details(to, ok, result), self.seq);
        let (status, body) = bt::send(&self.http, &self.token, &url, &msg).await?;
        println!("-> response to {}: {status} {body}", to.command);
        Ok(())
    }
}

/// The next Better Together command, or None after `wait`.
async fn next(events: &mut tokio::sync::broadcast::Receiver<event_hub::Event>, wait: Duration) -> Option<Message> {
    let deadline = tokio::time::Instant::now() + wait;
    loop {
        let ev = tokio::time::timeout_at(deadline, events.recv()).await.ok()?.ok()?;
        if ev.kind != EventKind::BetterTogether {
            continue;
        }
        match serde_json::from_str::<Message>(&ev.json) {
            Ok(m) => {
                println!("<- {} from {}: {}", m.command, m.registration_id, m.command_details);
                return Some(m);
            }
            Err(e) => println!("<- unreadable command: {e}"),
        }
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt().with_env_filter(std::env::var("RUST_LOG").unwrap_or_else(|_| "info".into())).init();
    let o = opts();
    let client = TeamsClient::new().await?;
    let oid = client.object_id().context("no object id for the signed-in user")?;
    let token = client.skype_token_value()?;
    let mut events = event_hub::subscribe();
    tokio::spawn(async {
        if let Err(e) = teams_cli::trouter::listen(teams_cli::trouter::ListenOptions::EMBEDDED, std::future::pending).await {
            eprintln!("trouter: {e:#}");
        }
    });
    let (surl, epid) = loop {
        if let Some(ep) = teams_cli::trouter::current_endpoint() {
            break ep;
        }
        tokio::time::sleep(Duration::from_millis(200)).await;
    };
    // Give the registrations a moment.
    tokio::time::sleep(Duration::from_secs(3)).await;
    let me = Endpoint::from_surl(&epid, &surl);
    println!("phone endpoint {} at {}", me.id, me.url);
    let mut caps = vec![serde_json::json!("BETTER_TOGETHER")];
    if o.wired {
        caps.push(serde_json::json!("WIRED_CONNECTION"));
    }
    let details = serde_json::json!({
        "deviceName": o.name,
        "clientType": "ipphone",
        "clientVersion": format!("OST/{}", env!("CARGO_PKG_VERSION")),
        "endpointSignature": o.signature,
        "capabilities": caps,
        "salt": [o.salt],
    });
    let mut phone = Phone { http: client.http().clone(), token, me, seq: 0, details };
    let beacon = advertise(&o, &oid).ok();

    let mut desktop: Option<(String, String)> = None;
    if o.pair {
        let peers = bt::discover(&phone.http, &phone.token, bt::REGISTRAR_URL).await?;
        let peers: Vec<_> = peers.into_iter().filter(|p| p.id != phone.me.id).collect();
        println!("desktops: {:?}", peers.iter().map(|p| (&p.id, &p.app_id, &p.platform)).collect::<Vec<_>>());
        let mut broadcasts = Vec::new();
        for p in peers.iter().filter(|p| o.desktop.as_ref().is_none_or(|d| *d == p.id)) {
            match phone.send(&p.url, command::BROADCAST, serde_json::json!({"targetEndpointId": p.id})).await {
                Ok(m) => broadcasts.push((m.debug_content.cause_id.clone(), p.clone())),
                Err(e) => println!("broadcast to {}: {e:#}", p.id),
            }
        }
        // The desktops near enough answer with their name.
        while desktop.is_none() {
            let Some(m) = next(&mut events, Duration::from_secs(30)).await else { break };
            if m.name() != command::RESPONSE {
                continue;
            }
            let d = m.details();
            let cause = d.get("requestCauseId").and_then(|v| v.as_str()).unwrap_or_default();
            if let Some((_, p)) = broadcasts.iter().find(|(c, _)| c == cause) {
                println!("desktop {} answered: {}", p.id, d);
                if d.get("statusCode").and_then(|v| v.as_u64()) == Some(200) {
                    desktop = Some((p.id.clone(), p.url.clone()));
                }
            }
        }
        let Some((id, url)) = desktop.clone() else {
            if let Some(b) = beacon {
                stop_advertising(b);
            }
            bail!("no desktop answered the broadcast");
        };
        let pair = phone.send(&url, command::PAIR, serde_json::json!({"targetEndpointId": id})).await?;
        let answer = loop {
            let Some(m) = next(&mut events, Duration::from_secs(bt::PAIR_PROMPT_SECS + 15)).await else { break None };
            if m.name() == command::RESPONSE && m.details().get("requestCauseId").and_then(|v| v.as_str()) == Some(pair.cause_id()) {
                break Some(m.details());
            }
        };
        match answer {
            Some(d) if d.get("accepted").and_then(|v| v.as_bool()) == Some(true) => {
                println!("PAIRED with {id}");
                bt::set_paired_ids(vec![id.clone()]);
            }
            other => {
                println!("NOT PAIRED: {other:?}");
                desktop = None;
            }
        }
    }

    // Serve the desktop until it unpairs or time runs out.
    let until = tokio::time::Instant::now() + Duration::from_secs(o.minutes * 60);
    while let Some(m) = next(&mut events, until.saturating_duration_since(tokio::time::Instant::now())).await {
        let salt = serde_json::json!({"salt": [o.salt]});
        match m.name().as_str() {
            command::KEEP_ALIVE | command::LOCK | command::UNLOCK => phone.respond(&m, true, salt).await?,
            command::UNPAIR => {
                phone.respond(&m, true, salt).await?;
                println!("UNPAIRED by desktop {}", m.registration_id);
                bt::set_paired_ids(Vec::new());
                desktop = None;
                break;
            }
            command::RESPONSE => {}
            other => {
                // Teams answers commands it doesn't know with INVALID_COMMAND.
                phone.respond(&m, false, serde_json::json!({"errorCode": "INVALID_COMMAND", "salt": [o.salt]})).await?;
                println!("(not a phone command: {other})");
            }
        }
    }
    if let Some((id, url)) = desktop {
        println!("still paired with {id} ({url})");
    }
    if let Some(b) = beacon {
        stop_advertising(b);
    }
    Ok(())
}

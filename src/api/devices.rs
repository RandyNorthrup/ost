//! Teams' device store (Store ▸ Devices), as Teams desktop reads it
//! (docs/spec/store.md "Devices"; measured on winpc 2026-11-20, Teams'
//! worker modules 2636 and 398085).
//!
//! - **Catalog:** with ECS `marketplace.enableCatalogOneCdn` (on) Teams asks
//!   `{catalogOneCdnBaseUrl}/{catalogOneCdnVersionTTL}/pointer` for the
//!   catalog's version (a date such as `2026/11/20`), then
//!   `{base}/{catalogOneCdnTTL}/{version}/{MARKET}_{locale}/AllDevices` (every
//!   device) and `…/{deviceId}` (one device's details). Without it:
//!   `{deviceStoreCatalogCDNHost}/catalogdata/{MARKET}_{locale}/AllDevices`.
//!   No sign-in is needed.
//! - **Collections** (ECS `extensibility.storeDevicesCollections`): each
//!   names a catalog collection number its devices carry; Featured lists
//!   the devices marked `isFeatured`.
//! - **Order:** Teams' default sort, Availability (Available, Low stock,
//!   Available in 3 weeks, On back order, Out of stock, then the rest), then
//!   the device id compared as text.

use std::sync::Mutex;
use std::time::{Duration, Instant};

use anyhow::{Context, Result};
use serde::Serialize;

use super::client::TeamsClient;
use crate::i18n::tr;

/// One of the Devices menu's collections, in Teams' order.
pub struct DeviceCollection {
    /// The page's key (`device:co:<key>` in Teams).
    pub key: &'static str,
    /// The catalog collection number its devices carry (Featured: 24,
    /// which Teams lists from `isFeatured`).
    pub linked: u32,
    /// Fluent icon (Teams' storeGroupCollectionIconMap).
    pub icon: &'static str,
}

pub const COLLECTIONS: [DeviceCollection; 8] = [
    DeviceCollection {
        key: "featured",
        linked: 24,
        icon: "star",
    },
    DeviceCollection {
        key: "headsets",
        linked: 9,
        icon: "headset",
    },
    DeviceCollection {
        key: "webcameras",
        linked: 5,
        icon: "video",
    },
    DeviceCollection {
        key: "speakerphones",
        linked: 8,
        icon: "speaker-2",
    },
    DeviceCollection {
        key: "deskphonesandteamsdisplays",
        linked: 7,
        icon: "device-meeting-room",
    },
    DeviceCollection {
        key: "monitors",
        linked: 11,
        icon: "desktop",
    },
    DeviceCollection {
        key: "teamsrooms",
        linked: 6,
        icon: "surface-hub",
    },
    DeviceCollection {
        key: "roomsystemsaccessories",
        linked: 10,
        icon: "device-meeting-room-remote",
    },
];

/// A collection's title and description, as Teams words them.
pub fn collection_text(key: &str) -> (String, String) {
    match key {
        "featured" => (tr("Featured"), String::new()),
        "headsets" => (
            tr("Headsets"),
            tr(
                "Keep focused in calls and meetings with headsets designed for comfort and clear communication. ",
            ),
        ),
        "webcameras" => (
            tr("Web cameras"),
            tr(
                "Find the web camera that suits your needs, whether you’re at home or in the office.",
            ),
        ),
        "speakerphones" => (
            tr("Speakerphones"),
            tr("Make sure everyone in the meeting is heard with these speakerphones."),
        ),
        "deskphonesandteamsdisplays" => (
            tr("Desk phones & Teams displays"),
            tr("Find the best desk phones with support for Teams right out of the box. "),
        ),
        "monitors" => (
            tr("Monitors"),
            tr("Turn any desk into a collaboration hub."),
        ),
        "teamsrooms" => (
            tr("Teams Rooms"),
            tr("Turn meeting rooms into Teams Rooms optimized for hybrid meetings."),
        ),
        "roomsystemsaccessories" => (
            tr("Room systems accessories"),
            tr("Elevate your meetings with accessories designed for small or large rooms."),
        ),
        _ => (String::new(), String::new()),
    }
}

/// A device as a collection page lists it.
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct Device {
    pub id: String,
    pub name: String,
    pub maker: String,
    pub short: String,
    /// The catalog's thumbnail (https only).
    pub image: String,
    pub image_alt: String,
    pub price: f64,
    /// As Teams writes it for the market ("$66.38").
    pub price_text: String,
    /// Teams' availability name (Available, OutOfStock…).
    pub availability: String,
}

/// The market Teams uses (MARKET_MAPPING; the United States for this
/// tenant) and its catalog locale.
pub const MARKET: &str = "US";
pub const LOCALE: &str = "en-us";

/// "$1,234.50", as Intl.NumberFormat("en-US", {style: "currency",
/// currency: "USD"}) writes it.
pub fn price_text(v: f64) -> String {
    let cents = (v * 100.0).round() as i64;
    let (whole, frac) = (cents / 100, (cents % 100).abs());
    let digits = whole.abs().to_string();
    let mut grouped = String::new();
    for (i, c) in digits.chars().enumerate() {
        if i > 0 && (digits.len() - i) % 3 == 0 {
            grouped.push(',');
        }
        grouped.push(c);
    }
    format!("{}${grouped}.{frac:02}", if whole < 0 { "-" } else { "" })
}

/// Teams' availability names, by the catalog's number (module 74269 `Hf`).
fn availability_name(n: i64) -> &'static str {
    match n {
        1 => "Available",
        2 => "OutOfStock",
        3 => "ComingSoon",
        4 => "OnBackOrder",
        5 => "EndOfLife",
        6 => "LowStock",
        7 => "NoShopAvailable",
        8 => "SurfaceHub",
        9 => "FastTrack",
        10 => "PreOrder",
        11 => "CallToOrder",
        12 => "AvailableIn3Weeks",
        _ => "Unknown",
    }
}

/// The rank Teams' Availability sort gives (module 398085 `G`).
fn availability_rank(name: &str) -> usize {
    [
        "Available",
        "LowStock",
        "AvailableIn3Weeks",
        "OnBackOrder",
        "OutOfStock",
    ]
    .iter()
    .position(|a| *a == name)
    .unwrap_or(5)
}

fn https(s: &str) -> String {
    if s.starts_with("https://") {
        s.to_string()
    } else {
        String::new()
    }
}

pub fn device_from(d: &serde_json::Value) -> Device {
    let s = |k: &str| {
        d.get(k)
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .trim()
            .to_string()
    };
    let price = d.get("price").and_then(|v| v.as_f64()).unwrap_or(0.0);
    Device {
        id: d
            .get("deviceId")
            .map(|v| v.to_string().trim_matches('"').to_string())
            .unwrap_or_default(),
        name: s("deviceName"),
        maker: s("manufacturerName"),
        short: s("shortDescription"),
        image: https(
            d.pointer("/thumbnailImage/blobURI")
                .and_then(|v| v.as_str())
                .unwrap_or_default(),
        ),
        image_alt: d
            .pointer("/thumbnailImage/altText")
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_string(),
        price,
        price_text: price_text(price),
        availability: availability_name(
            d.get("availabilityStatus")
                .and_then(|v| v.as_i64())
                .unwrap_or(0),
        )
        .to_string(),
    }
}

/// A collection's devices from the catalog, in Teams' default order.
pub fn collection_devices(all: &[serde_json::Value], key: &str) -> Vec<Device> {
    let Some(c) = COLLECTIONS.iter().find(|c| c.key == key) else {
        return Vec::new();
    };
    // Teams' catalog filter (filterNullDeviceContent): devices without a
    // name or short description are left out.
    let mut out: Vec<Device> = all
        .iter()
        .filter(|d| {
            if c.key == "featured" {
                d.get("isFeatured")
                    .and_then(|v| v.as_bool())
                    .unwrap_or(false)
            } else {
                d.get("collections")
                    .and_then(|v| v.as_array())
                    .is_some_and(|l| l.iter().any(|n| n.as_u64() == Some(c.linked as u64)))
            }
        })
        .map(device_from)
        .filter(|d| !d.name.is_empty() && !d.short.is_empty())
        .collect();
    out.sort_by(|a, b| {
        availability_rank(&a.availability)
            .cmp(&availability_rank(&b.availability))
            .then_with(|| a.id.cmp(&b.id))
    });
    out
}

fn setting_str(key: &str, default: &str) -> String {
    super::ecs::setting("marketplace", key)
        .and_then(|v| v.as_str().map(str::to_string))
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| default.to_string())
}

/// Where the catalog lives now (`…/{MARKET}_{locale}/` with a trailing
/// slash), asking OneCDN's pointer for its version.
async fn catalog_root(client: &TeamsClient) -> Result<String> {
    let one_cdn = super::ecs::setting("marketplace", "enableCatalogOneCdn")
        .and_then(|v| v.as_bool())
        .unwrap_or(true);
    let market = format!("{MARKET}_{LOCALE}");
    if !one_cdn {
        let host = setting_str(
            "deviceStoreCatalogCDNHost",
            "https://devicescatalog.teams.cdn.office.net",
        );
        return Ok(format!("{host}/catalogdata/{market}/"));
    }
    let base = setting_str(
        "catalogOneCdnBaseUrl",
        "https://res.cdn.office.net/devicescatalog",
    );
    let ttl = setting_str("catalogOneCdnTTL", "1httl");
    let vttl = setting_str("catalogOneCdnVersionTTL", "5mttl");
    // The pointer's body is the bare version (`2026/11/20`, not JSON).
    let version = client
        .http()
        .get(format!("{base}/{vttl}/pointer"))
        .send()
        .await?
        .error_for_status()
        .context("Device catalog version")?
        .text()
        .await?;
    let version = version.trim().trim_matches('"').to_string();
    // A version is a date path (yyyy/mm/dd).
    anyhow::ensure!(
        version.split('/').count() == 3 && version.bytes().all(|b| b.is_ascii_digit() || b == b'/'),
        "Unexpected device catalog version"
    );
    Ok(format!("{base}/{ttl}/{version}/{market}/"))
}

/// Every device in the catalog (kept an hour, as the CDN's TTL).
pub async fn all_devices(client: &TeamsClient) -> Result<std::sync::Arc<Vec<serde_json::Value>>> {
    static CACHE: Mutex<Option<(Instant, std::sync::Arc<Vec<serde_json::Value>>)>> =
        Mutex::new(None);
    if let Some((at, v)) = CACHE.lock().ok().and_then(|c| c.clone())
        && at.elapsed() < Duration::from_secs(3600)
    {
        return Ok(v);
    }
    let root = catalog_root(client).await?;
    let v: Vec<serde_json::Value> = client
        .http()
        .get(format!("{root}AllDevices"))
        .send()
        .await?
        .error_for_status()
        .context("Device catalog")?
        .json()
        .await?;
    let v = std::sync::Arc::new(v);
    if let Ok(mut c) = CACHE.lock() {
        *c = Some((Instant::now(), v.clone()));
    }
    Ok(v)
}

/// A collection page: its title, description and devices.
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct DevicePage {
    pub key: String,
    pub title: String,
    pub description: String,
    pub devices: Vec<Device>,
}

pub async fn collection(client: &TeamsClient, key: &str) -> Result<DevicePage> {
    anyhow::ensure!(
        COLLECTIONS.iter().any(|c| c.key == key),
        "No such device collection"
    );
    let all = all_devices(client).await?;
    let (title, description) = collection_text(key);
    Ok(DevicePage {
        key: key.to_string(),
        title: title.trim().to_string(),
        description: description.trim().to_string(),
        devices: collection_devices(&all, key),
    })
}

/// One of a device's Highlights or Tech Specs rows.
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct Entry {
    pub key: String,
    pub value: String,
}

/// A device's details page (Teams' storeDeviceDetails).
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct DeviceDetails {
    pub device: Device,
    /// The large picture(s) for the carousel.
    pub images: Vec<String>,
    pub full_description: String,
    pub highlights: Vec<Entry>,
    pub tech_specs: Vec<Entry>,
    /// Who fulfils orders ("UC": UnifiedCommunications.com).
    pub fulfiller: String,
}

fn entries(v: Option<&serde_json::Value>) -> Vec<Entry> {
    v.and_then(|v| v.as_array())
        .into_iter()
        .flatten()
        .filter_map(|e| {
            Some(Entry {
                key: e.get("Key")?.as_str()?.trim().to_string(),
                // The catalog writes line breaks as "\n" (sometimes also an
                // escaped "\\n"); Teams shows one line each.
                value: e
                    .get("Value")?
                    .as_str()?
                    .replace("\\n", "\n")
                    .lines()
                    .map(str::trim)
                    .filter(|l| !l.is_empty())
                    .collect::<Vec<_>>()
                    .join("\n"),
            })
        })
        .collect()
}

pub fn details_from(d: &serde_json::Value) -> DeviceDetails {
    let images: Vec<String> = d
        .pointer("/images/large")
        .and_then(|v| v.as_array())
        .into_iter()
        .flatten()
        .filter_map(|i| i.get("blobURI")?.as_str().map(https))
        .filter(|u| !u.is_empty())
        .collect();
    DeviceDetails {
        device: device_from(d),
        images,
        full_description: d
            .get("fullDescription")
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .trim()
            .to_string(),
        highlights: entries(d.get("overview")),
        tech_specs: entries(d.get("techSpecs")),
        fulfiller: d
            .get("fulfillerPartner")
            .and_then(|v| v.as_str())
            .unwrap_or_default()
            .to_string(),
    }
}

pub async fn details(client: &TeamsClient, id: &str) -> Result<DeviceDetails> {
    anyhow::ensure!(
        !id.is_empty() && id.bytes().all(|b| b.is_ascii_digit()),
        "Not a device"
    );
    let root = catalog_root(client).await?;
    let d: serde_json::Value = client
        .http()
        .get(format!("{root}{id}"))
        .send()
        .await?
        .error_for_status()
        .context("Device details")?
        .json()
        .await?;
    Ok(details_from(&d))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dev(id: u32, cols: &[u32], featured: bool, status: i64) -> serde_json::Value {
        serde_json::json!({"deviceId": id, "deviceName": format!("D{id}"), "manufacturerName": "M",
            "shortDescription": "S", "thumbnailImage": {"blobURI": "https://x/i.png", "altText": "A"},
            "price": 66.38, "collections": cols, "isFeatured": featured, "availabilityStatus": status})
    }

    #[test]
    fn collections_and_order_follow_teams() {
        let all = vec![
            dev(1004, &[9], false, 1),
            dev(100, &[9, 17], false, 1),
            dev(1000, &[9], true, 1),
            dev(7, &[9], false, 4),
            dev(5, &[5], false, 1),
        ];
        // Measured on winpc: Headsets lists 100, 1000, 1004 … (the id as
        // text) with out-of-stock ones after.
        let h: Vec<String> = collection_devices(&all, "headsets")
            .into_iter()
            .map(|d| d.id)
            .collect();
        assert_eq!(h, ["100", "1000", "1004", "7"]);
        let f: Vec<String> = collection_devices(&all, "featured")
            .into_iter()
            .map(|d| d.id)
            .collect();
        assert_eq!(f, ["1000"]);
        assert!(collection_devices(&all, "nope").is_empty());
    }

    #[test]
    fn prices_read_as_teams_writes_them() {
        assert_eq!(price_text(66.38), "$66.38");
        assert_eq!(price_text(5141.18), "$5,141.18");
        assert_eq!(price_text(146.0), "$146.00");
    }

    #[test]
    fn details_keep_highlights_and_specs() {
        let d = serde_json::json!({"deviceId": 100, "deviceName": "ADAPT 165T USB C II", "manufacturerName": "EPOS",
            "shortDescription": "Wired\n", "price": 66.38, "availabilityStatus": 1, "fulfillerPartner": "UC",
            "fullDescription": "Long\n", "images": {"large": [{"blobURI": "https://x/l.png"}, {"blobURI": "http://bad"}]},
            "overview": [{"Key": "Call quality ", "Value": "Clear."}],
            "techSpecs": [{"Key": "Included", "Value": "Headset \\n\nPouch \\n"}]});
        let r = details_from(&d);
        assert_eq!(r.images, ["https://x/l.png"]);
        assert_eq!(r.device.short, "Wired");
        assert_eq!(r.highlights[0].key, "Call quality");
        assert_eq!(r.tech_specs[0].value, "Headset\nPouch");
        assert_eq!(r.fulfiller, "UC");
    }
}

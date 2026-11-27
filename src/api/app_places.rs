//! The meetings Teams' quick-start dialog ("Let's go", the Store's
//! contextless config picker) offers as places to use an app. Teams' worker
//! resolver `appInstallOptions` (inner~d, 2026-11-27) takes your calendar's
//! Teams meetings: a private one by its meeting chat (`19:meeting_…`), a
//! channel meeting by its channel and post; then the ones still to come,
//! soonest end first, before the past ones, latest end first, each place
//! once.

use anyhow::Result;
use serde::Serialize;

use super::calendar::CalendarEvent;
use super::client::TeamsClient;

/// One meeting place.
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct PlaceMeeting {
    /// The meeting chat (private meetings), else empty.
    pub chat_id: String,
    /// A channel meeting's channel and its post.
    pub channel_id: String,
    pub message_id: String,
    pub title: String,
    /// When it ends (ISO).
    pub end: String,
}

/// The calendar's meetings in Teams' order (`now` splits upcoming from
/// past).
pub fn meetings_from(events: &[CalendarEvent], now: jiff::Timestamp) -> Vec<PlaceMeeting> {
    let mut list: Vec<(jiff::Timestamp, PlaceMeeting)> = events
        .iter()
        .filter(|e| !e.is_cancelled && !e.subject.is_empty())
        .filter_map(|e| {
            let end = crate::clock::parse_instant(&e.end_utc)?;
            let m = if !e.channel_id.is_empty() {
                if e.channel_message_id.is_empty() {
                    return None;
                }
                PlaceMeeting {
                    channel_id: e.channel_id.clone(),
                    message_id: e.channel_message_id.clone(),
                    ..Default::default()
                }
            } else {
                let thread = crate::calling::breakout::thread_of_join_url(e.join_url.as_deref()?)?;
                PlaceMeeting {
                    chat_id: thread,
                    ..Default::default()
                }
            };
            Some((
                end,
                PlaceMeeting {
                    title: e.subject.clone(),
                    end: e.end_utc.clone(),
                    ..m
                },
            ))
        })
        .collect();
    let (mut past, mut ahead): (Vec<_>, Vec<_>) = list.drain(..).partition(|(end, _)| *end < now);
    ahead.sort_by_key(|(end, _)| *end);
    past.sort_by_key(|(end, _)| std::cmp::Reverse(*end));
    let mut seen = std::collections::HashSet::new();
    ahead
        .into_iter()
        .chain(past)
        .map(|(_, m)| m)
        .filter(|m| {
            seen.insert(if m.chat_id.is_empty() {
                m.message_id.clone()
            } else {
                m.chat_id.clone()
            })
        })
        .collect()
}

/// Your Teams meetings from a month before to a month after now.
pub async fn meetings(client: &TeamsClient) -> Result<Vec<PlaceMeeting>> {
    let now = jiff::Timestamp::now();
    let fmt = crate::clock::iso_secs;
    let events = super::calendar::calendar_view(
        client,
        &fmt(now - crate::clock::days(30)),
        &fmt(now + crate::clock::days(30)),
    )
    .await?;
    Ok(meetings_from(&events, now))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ev(subject: &str, end: &str, join: &str, channel: &str, post: &str) -> CalendarEvent {
        CalendarEvent {
            subject: subject.into(),
            end_utc: end.into(),
            join_url: (!join.is_empty()).then(|| join.to_string()),
            channel_id: channel.into(),
            channel_message_id: post.into(),
            ..Default::default()
        }
    }

    #[test]
    fn upcoming_first_then_past_each_place_once() {
        let join = |t: &str| {
            format!(
                "https://teams.microsoft.com/l/meetup-join/19%3ameeting_{t}%40thread.v2/0?context=x"
            )
        };
        let events = [
            ev("Old sync", "2026-11-20T10:00:00Z", &join("a"), "", ""),
            ev("Design review", "2026-11-30T10:00:00Z", &join("b"), "", ""),
            ev(
                "Weekly team sync",
                "2026-11-28T10:00:00Z",
                &join("c"),
                "",
                "",
            ),
            ev(
                "Weekly team sync",
                "2026-12-05T10:00:00Z",
                &join("c"),
                "",
                "",
            ),
            ev(
                "Channel meet",
                "2026-11-25T10:00:00Z",
                "",
                "19:x@thread.tacv2",
                "1764000000000",
            ),
            ev("No link", "2026-11-29T10:00:00Z", "", "", ""),
        ];
        let now = crate::clock::parse_instant("2026-11-27T12:00:00Z").unwrap();
        let got = meetings_from(&events, now);
        assert_eq!(
            got.iter().map(|m| m.title.as_str()).collect::<Vec<_>>(),
            [
                "Weekly team sync",
                "Design review",
                "Channel meet",
                "Old sync"
            ]
        );
        assert_eq!(got[0].chat_id, "19:meeting_c@thread.v2");
        assert_eq!(got[2].channel_id, "19:x@thread.tacv2");
        assert_eq!(got[2].message_id, "1764000000000");
    }
}

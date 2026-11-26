//! Time on jiff, in the shapes Teams and Graph use.
//!
//! OST used chrono until it was declared unmaintained (RUSTSEC-2026-0543);
//! these helpers keep chrono's results where OST depends on them: its RFC
//! 3339 grammar (the times every Teams and Graph reply carries), its
//! timestamp shapes (`.000Z` milliseconds, `+00:00`), whole-millisecond
//! epoch values, and local times in the system's time zone (TZ, else
//! /etc/localtime) with chrono's answers for times that a DST change skips
//! or repeats. Where chrono 0.4.45 answered differently only within the
//! first second of a skipped hour or the last second of a repeated one
//! (its zone-file and POSIX-rule lookups also disagreed there), jiff's
//! reading is used.

use jiff::civil;
use jiff::tz::{AmbiguousOffset, Offset, TimeZone};
use jiff::{SignedDuration, Timestamp, ZonedDateTime};

/// The system's time zone: `TZ`, else /etc/localtime, else UTC.
pub fn local_zone() -> TimeZone {
    TimeZone::system()
}

/// Now, in the system's time zone.
pub fn local_now() -> ZonedDateTime {
    Timestamp::now().to_zoned_datetime(local_zone())
}

/// A moment in the system's time zone.
pub fn local(t: Timestamp) -> ZonedDateTime {
    t.to_zoned_datetime(local_zone())
}

/// A moment in UTC.
pub fn utc(t: Timestamp) -> ZonedDateTime {
    t.to_zoned_datetime(TimeZone::UTC)
}

/// The system zone's current offset from UTC, in seconds (east positive).
pub fn local_offset_seconds() -> i32 {
    local_now().offset().seconds()
}

/// Milliseconds since the Unix epoch, rounded down (chrono's
/// `timestamp_millis`).
pub fn millis(t: Timestamp) -> i64 {
    t.as_nanosecond().div_euclid(1_000_000) as i64
}

/// Seconds since the Unix epoch, rounded down (chrono's `timestamp`).
pub fn seconds(t: Timestamp) -> i64 {
    t.as_nanosecond().div_euclid(1_000_000_000) as i64
}

/// Now, in milliseconds since the Unix epoch.
pub fn now_ms() -> i64 {
    millis(Timestamp::now())
}

/// Now, in nanoseconds since the Unix epoch.
pub fn now_ns() -> i128 {
    Timestamp::now().as_nanosecond()
}

/// A moment from milliseconds since the Unix epoch (None out of range).
pub fn from_ms(ms: i64) -> Option<Timestamp> {
    Timestamp::from_millisecond(ms).ok()
}

/// RFC 3339 in UTC with milliseconds and `Z` ("2026-11-20T16:00:00.000Z"),
/// as Teams writes its times.
pub fn iso_ms(t: Timestamp) -> String {
    format(t, "%Y-%m-%dT%H:%M:%S%.3fZ")
}

/// Now as `iso_ms`.
pub fn now_iso_ms() -> String {
    iso_ms(Timestamp::now())
}

/// Milliseconds since the epoch as `iso_ms`.
pub fn ms_iso(ms: i64) -> Option<String> {
    from_ms(ms).map(iso_ms)
}

/// RFC 3339 in UTC to the second with `Z` ("2026-11-20T16:00:00Z").
pub fn iso_secs(t: Timestamp) -> String {
    format(t, "%Y-%m-%dT%H:%M:%SZ")
}

/// RFC 3339 in UTC with `+00:00` and only the fraction digits it needs (3,
/// 6 or 9): chrono's `to_rfc3339` on a UTC time, which OST hands to QML.
pub fn rfc3339(t: Timestamp) -> String {
    rfc3339_in(&utc(t))
}

/// RFC 3339 with the time's own offset ("2026-11-20T11:00:00.5-05:00"):
/// chrono's `to_rfc3339`.
pub fn rfc3339_in(t: &ZonedDateTime) -> String {
    let ns = t.timestamp().subsec_nanosecond().rem_euclid(1_000_000_000);
    let frac = if ns == 0 {
        ""
    } else if ns % 1_000_000 == 0 {
        "%.3f"
    } else if ns % 1_000 == 0 {
        "%.6f"
    } else {
        "%.9f"
    };
    format(t, &format!("%Y-%m-%dT%H:%M:%S{frac}%:z"))
}

/// strftime, or an empty string where the pattern can't be formatted.
pub fn format(t: impl Into<jiff::fmt::strtime::BrokenDownTime>, pattern: &str) -> String {
    jiff::fmt::strtime::format(pattern, t).unwrap_or_default()
}

/// A time string that isn't RFC 3339.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct InvalidTime;

impl std::fmt::Display for InvalidTime {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("not an RFC 3339 time")
    }
}

impl std::error::Error for InvalidTime {}

/// An RFC 3339 time ("2026-11-20T16:00:00.1234567+01:00") with its own
/// offset, by chrono's grammar: `T`, `t` or a space between date and time,
/// any number of fraction digits (past nine ignored), `Z`/`z` or `±hh:mm`
/// (U+2212 as minus too) under 24 hours, and second 60 as the next second.
/// Times past jiff's range (years 9999 and -9999 at their ends) are held at
/// its first or last moment.
pub fn parse_rfc3339(s: &str) -> Result<ZonedDateTime, InvalidTime> {
    let (ts, offset) = parse_parts(s).ok_or(InvalidTime)?;
    Ok(ts.to_zoned_datetime(TimeZone::fixed(offset)))
}

/// `parse_rfc3339`'s moment.
pub fn parse_instant(s: &str) -> Option<Timestamp> {
    parse_parts(s).map(|(t, _)| t)
}

fn parse_parts(s: &str) -> Option<(Timestamp, Offset)> {
    let b = s.as_bytes();
    if b.len() < 19 {
        return None;
    }
    let d = |i: usize| b[i].is_ascii_digit().then(|| i64::from(b[i] - b'0'));
    let two = |i: usize| Some(d(i)? * 10 + d(i + 1)?);
    let year = d(0)? * 1000 + d(1)? * 100 + d(2)? * 10 + d(3)?;
    if b[4] != b'-' || b[7] != b'-' || !matches!(b[10], b'T' | b't' | b' ') {
        return None;
    }
    if b[13] != b':' || b[16] != b':' {
        return None;
    }
    let (month, day) = (two(5)?, two(8)?);
    let (hour, minute, mut second) = (two(11)?, two(14)?, two(17)?);
    let date = civil::Date::new(year as i16, month as i8, day as i8).ok()?;
    let mut extra = 0;
    if second == 60 {
        // A leap second, as chrono reads it: the next second.
        second = 59;
        extra = 1;
    }
    if hour > 23 || minute > 59 || second > 59 {
        return None;
    }
    let mut rest = &s[19..];
    let mut nanos: i64 = 0;
    if let Some(frac) = rest.strip_prefix('.') {
        let digits = frac.bytes().take_while(u8::is_ascii_digit).count();
        if digits == 0 {
            return None;
        }
        for (i, c) in frac.bytes().take(9).enumerate() {
            if i >= digits {
                break;
            }
            nanos += i64::from(c - b'0') * 10_i64.pow(8 - i as u32);
        }
        rest = &frac[digits..];
    }
    let offset = match rest.as_bytes().first()? {
        b'Z' | b'z' => {
            rest = &rest[1..];
            0
        }
        _ => {
            let (neg, tail) = if let Some(t) = rest.strip_prefix('+') {
                (false, t)
            } else if let Some(t) = rest.strip_prefix('-') {
                (true, t)
            } else if let Some(t) = rest.strip_prefix('\u{2212}') {
                (true, t)
            } else {
                return None;
            };
            let t = tail.as_bytes();
            if t.len() < 5 || t[2] != b':' {
                return None;
            }
            let dig = |i: usize| t[i].is_ascii_digit().then(|| i32::from(t[i] - b'0'));
            let h = dig(0)? * 10 + dig(1)?;
            if !(b'0'..=b'5').contains(&t[3]) {
                return None;
            }
            let m = dig(3)? * 10 + dig(4)?;
            rest = &tail[5..];
            let secs = h * 3600 + m * 60;
            if secs >= 86_400 {
                return None;
            }
            if neg { -secs } else { secs }
        }
    };
    if !rest.is_empty() {
        return None;
    }
    let offset = Offset::from_seconds(offset).ok()?;
    let wall = date.at(hour as i8, minute as i8, second as i8, 0);
    // Seconds since the epoch of the wall time, then the offset, the leap
    // second and the fraction: no range limits before the last step.
    let days = i64::from(wall.date().since(civil::date(1970, 1, 1)).ok()?.get_days());
    let secs =
        days * 86_400 + hour * 3600 + minute * 60 + second + extra - i64::from(offset.seconds());
    let ns = i128::from(secs) * 1_000_000_000 + i128::from(nanos);
    let ts = Timestamp::from_nanosecond(ns).unwrap_or(if ns < 0 {
        Timestamp::MIN
    } else {
        Timestamp::MAX
    });
    Some((ts, offset))
}

/// A wall-clock time ("%Y-%m-%dT%H:%M:%S%.f", "%m/%d/%Y %H:%M:%S") with no
/// zone.
pub fn parse_naive(s: &str, pattern: &str) -> Option<civil::DateTime> {
    // Fraction digits past nine are ignored, as chrono did.
    if let Some(dot) = s.find('.') {
        let digits = s[dot + 1..].bytes().take_while(u8::is_ascii_digit).count();
        if digits > 9 {
            let cut = format!("{}{}", &s[..dot + 10], &s[dot + 1 + digits..]);
            return civil::DateTime::strptime(pattern, cut).ok();
        }
    }
    civil::DateTime::strptime(pattern, s).ok()
}

/// A wall-clock time read as UTC.
pub fn as_utc(dt: civil::DateTime) -> Option<Timestamp> {
    Offset::UTC.to_timestamp(dt).ok()
}

/// A date ("%Y-%m-%d").
pub fn parse_date(s: &str, pattern: &str) -> Option<civil::Date> {
    civil::Date::strptime(pattern, s).ok()
}

/// A wall-clock time in `tz` when it names one moment (chrono's `single`):
/// none in an hour a DST change repeats, nor in one it skips, except the
/// skipped hour's first instant, which is the change itself (chrono and
/// JavaScript's Date both read it so: a day starting at a midnight DST
/// change starts at the change).
pub fn single(tz: &TimeZone, dt: civil::DateTime) -> Option<ZonedDateTime> {
    match tz.to_ambiguous_timestamp(dt).offset() {
        AmbiguousOffset::Unambiguous { offset } => read(tz, offset, dt),
        AmbiguousOffset::Gap { before, .. } => gap_start(tz, before, dt),
        AmbiguousOffset::Fold { .. } => None,
    }
}

/// A wall-clock time in `tz` as chrono's `earliest` read it: in an hour a
/// DST change repeats, the reading at the smaller UTC offset (standard
/// time, the later moment; JavaScript's Date, so Teams, takes the other);
/// none in an hour it skips except that hour's first instant (see
/// `single`).
pub fn earliest(tz: &TimeZone, dt: civil::DateTime) -> Option<ZonedDateTime> {
    match tz.to_ambiguous_timestamp(dt).offset() {
        AmbiguousOffset::Unambiguous { offset } => read(tz, offset, dt),
        AmbiguousOffset::Gap { before, .. } => gap_start(tz, before, dt),
        AmbiguousOffset::Fold { before, after } => read(tz, before.min(after), dt),
    }
}

fn read(tz: &TimeZone, o: Offset, dt: civil::DateTime) -> Option<ZonedDateTime> {
    o.to_timestamp(dt)
        .ok()
        .map(|t| t.to_zoned_datetime(tz.clone()))
}

fn gap_start(tz: &TimeZone, before: Offset, dt: civil::DateTime) -> Option<ZonedDateTime> {
    let t = before.to_timestamp(dt).ok()?;
    let prior = t.checked_sub(SignedDuration::from_nanos(1)).ok()?;
    (tz.to_offset(prior) == before && tz.to_offset(t) != before)
        .then(|| t.to_zoned_datetime(tz.clone()))
}

/// `single` in the system's zone.
pub fn local_single(dt: civil::DateTime) -> Option<ZonedDateTime> {
    single(&local_zone(), dt)
}

/// `earliest` in the system's zone.
pub fn local_earliest(dt: civil::DateTime) -> Option<ZonedDateTime> {
    earliest(&local_zone(), dt)
}

/// `n` whole days of 24 hours (chrono's `Duration::days` on a time).
pub fn days(n: i64) -> SignedDuration {
    SignedDuration::from_hours(24 * n)
}

/// Whole days from `from` to `to` (chrono's `(to - from).num_days()`).
pub fn days_between(from: civil::Date, to: civil::Date) -> i64 {
    to.duration_since(from).as_hours() / 24
}

/// `d` moved by `n` calendar days (chrono's `NaiveDate + Duration::days`).
pub fn add_days(d: civil::Date, n: i64) -> civil::Date {
    d.checked_add(SignedDuration::from_hours(24 * n))
        .unwrap_or(d)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// US Eastern (DST from the second Sunday of March 02:00 to the first
    /// Sunday of November 02:00), without the system's tzdb.
    fn eastern() -> TimeZone {
        TimeZone::posix("EST5EDT,M3.2.0,M11.1.0").unwrap()
    }

    /// A zone whose DST starts at midnight (Chile's: the first Sunday of
    /// September from 00:00, back on the first Sunday of April).
    fn midnight_change() -> TimeZone {
        TimeZone::posix("<-04>4<-03>,M9.1.0/0,M4.1.0/0").unwrap()
    }

    fn wall(y: i16, mo: i8, d: i8, h: i8, mi: i8) -> civil::DateTime {
        civil::datetime(y, mo, d, h, mi, 0, 0)
    }

    fn iso(t: &Option<ZonedDateTime>) -> Option<String> {
        t.as_ref().map(|t| iso_ms(t.timestamp()))
    }

    #[test]
    fn rfc3339_reads_as_chrono_did() {
        let p = |s: &str| {
            parse_rfc3339(s)
                .ok()
                .map(|t| (rfc3339(t.timestamp()), t.offset().seconds()))
        };
        let ok = |s: &str, utc: &str, off: i32| assert_eq!(p(s), Some((utc.into(), off)), "{s}");
        ok("2026-11-20T16:00:00Z", "2026-11-20T16:00:00+00:00", 0);
        ok("2026-11-20t16:00:00z", "2026-11-20T16:00:00+00:00", 0);
        ok(
            "2026-11-20 17:30:00+01:30",
            "2026-11-20T16:00:00+00:00",
            5400,
        );
        ok(
            "2026-11-20T11:00:00-05:00",
            "2026-11-20T16:00:00+00:00",
            -18000,
        );
        ok(
            "2026-11-20T11:00:00\u{2212}05:00",
            "2026-11-20T16:00:00+00:00",
            -18000,
        );
        ok(
            "2026-11-20T16:00:00.1234567Z",
            "2026-11-20T16:00:00.123456700+00:00",
            0,
        );
        // Past nine digits the fraction is cut.
        ok(
            "2026-11-20T16:00:00.1234567891234Z",
            "2026-11-20T16:00:00.123456789+00:00",
            0,
        );
        // A leap second reads as the next second.
        ok("2026-12-31T23:59:60Z", "2027-01-01T00:00:00+00:00", 0);
        ok(
            "2026-11-20T16:00:00+23:59",
            "2026-11-19T16:01:00+00:00",
            86_340,
        );
        for bad in [
            "2026-11-20T16:00:00",
            "2026-11-20T16:00Z",
            "2026-11-20T16:00:00+24:00",
            "2026-11-20T16:00:00+05",
            "2026-11-20T16:00:00+0500",
            "2026-11-20T16:00:00+05:60",
            "2026-11-20T24:00:00Z",
            "2026-02-29T00:00:00Z",
            "2026-11-20T16:00:00.Z",
            "2026-11-20T16:00:00Z ",
            " 2026-11-20T16:00:00Z",
            "2026-11-20T16:00:00 Z",
            "2026-11-20T16:00:00UTC",
            "",
        ] {
            assert_eq!(p(bad), None, "{bad}");
        }
        // Past jiff's last moment: held there, ordered after everything.
        let never = parse_instant("9999-12-31T23:59:59.999Z").unwrap();
        assert_eq!(never, Timestamp::MAX);
        assert!(never > parse_instant("2026-11-20T16:00:00Z").unwrap());
    }

    #[test]
    fn timestamps_write_as_teams_reads_them() {
        let t = parse_instant("2026-11-20T16:00:00.1234567Z").unwrap();
        assert_eq!(iso_ms(t), "2026-11-20T16:00:00.123Z");
        assert_eq!(iso_secs(t), "2026-11-20T16:00:00Z");
        assert_eq!(rfc3339(t), "2026-11-20T16:00:00.123456700+00:00");
        assert_eq!(ms_iso(0).unwrap(), "1970-01-01T00:00:00.000Z");
        assert_eq!(ms_iso(-1).unwrap(), "1969-12-31T23:59:59.999Z");
        assert_eq!(millis(from_ms(-1).unwrap()), -1);
        assert_eq!(
            millis(Timestamp::new(-1, -500_000).unwrap()),
            -1001,
            "rounded down"
        );
        assert_eq!(seconds(Timestamp::new(-1, -5).unwrap()), -2);
        let local = parse_rfc3339("2026-11-20T11:00:00.5-05:00").unwrap();
        assert_eq!(rfc3339_in(&local), "2026-11-20T11:00:00.500-05:00");
        assert_eq!(format(&local, "%-I:%M %p"), "11:00 AM");
        assert_eq!(format(&local, "%Q"), "-0500");
        assert_eq!(format(&local, "%"), "");
    }

    #[test]
    fn wall_times_across_dst_changes() {
        let tz = eastern();
        // An ordinary time.
        assert_eq!(
            iso(&single(&tz, wall(2026, 11, 20, 9, 0))).as_deref(),
            Some("2026-11-20T14:00:00.000Z")
        );
        // The skipped hour (March 8, 02:00-03:00): none, except its first
        // instant, which is the change.
        assert_eq!(single(&tz, wall(2026, 3, 8, 2, 30)), None);
        assert_eq!(earliest(&tz, wall(2026, 3, 8, 2, 30)), None);
        assert_eq!(
            iso(&single(&tz, wall(2026, 3, 8, 2, 0))).as_deref(),
            Some("2026-03-08T07:00:00.000Z")
        );
        assert_eq!(
            iso(&single(&tz, wall(2026, 3, 8, 3, 0))).as_deref(),
            Some("2026-03-08T07:00:00.000Z")
        );
        // The repeated hour (November 1, 01:00-02:00): no single reading;
        // chrono's "earliest" was the standard-time one.
        assert_eq!(single(&tz, wall(2026, 11, 1, 1, 30)), None);
        assert_eq!(
            iso(&earliest(&tz, wall(2026, 11, 1, 1, 30))).as_deref(),
            Some("2026-11-01T06:30:00.000Z")
        );
        assert_eq!(
            iso(&single(&tz, wall(2026, 11, 1, 2, 0))).as_deref(),
            Some("2026-11-01T07:00:00.000Z")
        );
        // A day that starts at a DST change starts at the change.
        let chile = midnight_change();
        assert_eq!(
            iso(&single(&chile, wall(2026, 9, 6, 0, 0))).as_deref(),
            Some("2026-09-06T04:00:00.000Z")
        );
        assert_eq!(single(&chile, wall(2026, 9, 6, 0, 30)), None);
    }

    #[test]
    fn days_are_calendar_days() {
        let d = civil::date(2026, 3, 8);
        assert_eq!(add_days(d, -1), civil::date(2026, 3, 7));
        assert_eq!(add_days(d, 365), civil::date(2027, 3, 8));
        assert_eq!(days_between(civil::date(2026, 11, 1), d), -238);
        assert_eq!(days_between(d, civil::date(2026, 3, 9)), 1);
        // A day of 24 hours across the change is 25 wall-clock hours.
        let tz = eastern();
        let t = single(&tz, wall(2026, 10, 31, 12, 0)).unwrap();
        assert_eq!(format(&(&t + days(1)), "%m-%d %H:%M"), "11-01 11:00");
    }
}

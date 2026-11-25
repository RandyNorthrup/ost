//! Settings ▸ Calls ▸ Call handling and forwarding for Teams Phone users, as
//! Teams 26304 changes the call redirection settings (settings-app module
//! 30072: `Sh` forward all, `gG` also ring, `HD` unanswered calls, `Ow` /
//! `Z0` the two delays). Each takes the current `callRedirectionSettings`
//! and returns the whole object Teams posts to
//! `{mt}/beta/usersettings/{mri}/callredirectionsettings`.
//!
//! Targets: "Voicemail", "SingleTarget" (a person or number, its MRI in
//! `target`), "Group" (your call group), "MyDelegates", "DoNothing".

use serde_json::{Value, json};

/// Teams' delays (calling_forwarding_settings_delay_*), in seconds.
pub const DELAYS: [u64; 9] = [0, 5, 10, 15, 20, 30, 40, 50, 60];
/// Teams keeps the last three numbers or people you forwarded to.
pub const FAVORITE_TARGETS_MAX: usize = 3;

fn is(t: Option<&str>, want: &str) -> bool {
    t.is_some_and(|t| t.eq_ignore_ascii_case(want))
}

fn str_of<'a>(v: &'a Value, ptr: &str) -> Option<&'a str> {
    v.pointer(ptr).and_then(Value::as_str)
}

/// The settings with every object Teams sends present.
pub fn normalized(current: &Value) -> Value {
    let mut o = if current.is_object() {
        current.clone()
    } else {
        json!({})
    };
    for (k, dflt) in [
        (
            "callForwardingSettings",
            json!({ "isEnabled": false, "forwardingType": "Simultaneous", "targetType": "DoNothing", "target": null, "delaySeconds": 0 }),
        ),
        (
            "unansweredCallSettings",
            json!({ "isEnabled": true, "targetType": "Voicemail", "target": null, "delaySeconds": 20, "safeForward": false }),
        ),
        (
            "callGroupDetails",
            json!({ "callOrder": "simultaneous", "delaySeconds": 0, "targets": [] }),
        ),
        ("favoriteTargets", json!({ "targets": [] })),
    ] {
        if !o[k].is_object() {
            o[k] = dflt;
        }
    }
    o
}

/// Teams' `P`: a picked target joins the favourites (first, at most three).
fn add_favorite(o: &mut Value, target: &str) {
    if !o["favoriteTargets"]["targets"].is_array() {
        o["favoriteTargets"] = json!({ "targets": [] });
    }
    let list = o["favoriteTargets"]["targets"]
        .as_array_mut()
        .expect("array");
    if !list.iter().any(|t| t.as_str() == Some(target)) {
        list.insert(0, Value::String(target.to_string()));
    }
    list.truncate(FAVORITE_TARGETS_MAX);
}

/// Teams' `f`: the also-ring delay stays under the unanswered delay.
fn clamp_forward_delay(o: &mut Value) {
    let Some(un) = o["unansweredCallSettings"]["delaySeconds"]
        .as_u64()
        .filter(|d| *d > 0)
    else {
        return;
    };
    let fwd = o["callForwardingSettings"]["delaySeconds"]
        .as_u64()
        .unwrap_or(0);
    if fwd >= un {
        let i = DELAYS
            .iter()
            .position(|d| *d == un)
            .map(|i| i.saturating_sub(1))
            .unwrap_or(0);
        o["callForwardingSettings"]["delaySeconds"] = json!(DELAYS[i]);
    }
}

/// Teams' `HD`: what happens to unanswered calls.
pub fn unanswered(
    current: &Value,
    target_type: Option<&str>,
    voicemail_allowed: bool,
    target: Option<&str>,
) -> Value {
    let mut o = normalized(current);
    let x = match target_type {
        Some(t) if !t.is_empty() => t.to_string(),
        _ => {
            if o["unansweredCallSettings"]["isEnabled"].as_bool() == Some(true) {
                "Voicemail".into()
            } else {
                "DoNothing".into()
            }
        }
    };
    let u = &mut o["unansweredCallSettings"];
    u["isEnabled"] = json!(true);
    u["targetType"] = json!(x);
    u["target"] = Value::Null;
    u["safeForward"] = json!(false);
    match x.to_lowercase().as_str() {
        "singletarget" => u["target"] = target.map(|t| json!(t)).unwrap_or(Value::Null),
        "mydelegates" => u["safeForward"] = json!(true),
        "donothing" => u["isEnabled"] = json!(false),
        _ => {}
    }
    let fwd_on = o["callForwardingSettings"]["isEnabled"].as_bool() == Some(true);
    let fwd_type = str_of(&o, "/callForwardingSettings/targetType").map(str::to_string);
    let un_type = str_of(&o, "/unansweredCallSettings/targetType").map(str::to_string);
    if fwd_on && is(fwd_type.as_deref(), "MyDelegates") {
        if is(un_type.as_deref(), "MyDelegates") {
            let u = &mut o["unansweredCallSettings"];
            u["safeForward"] = json!(false);
            u["target"] = Value::Null;
            if voicemail_allowed {
                u["isEnabled"] = json!(true);
                u["safeForward"] = json!(true);
                u["targetType"] = json!("Voicemail");
            } else {
                u["isEnabled"] = json!(false);
                u["targetType"] = json!("DoNothing");
            }
        } else if o["unansweredCallSettings"]["isEnabled"].as_bool() == Some(true)
            && !is(un_type.as_deref(), "DoNothing")
        {
            o["unansweredCallSettings"]["safeForward"] = json!(true);
        }
    }
    let simultaneous = !fwd_on
        || is(
            str_of(&o, "/callForwardingSettings/forwardingType"),
            "Simultaneous",
        );
    let un_type = str_of(&o, "/unansweredCallSettings/targetType").map(str::to_string);
    if simultaneous && is(fwd_type.as_deref(), "Group") && is(un_type.as_deref(), "Group") {
        let u = &mut o["unansweredCallSettings"];
        if voicemail_allowed {
            u["isEnabled"] = json!(true);
            u["targetType"] = json!("Voicemail");
        } else {
            u["isEnabled"] = json!(false);
            u["targetType"] = json!("DoNothing");
        }
    }
    if let Some(t) = target {
        add_favorite(&mut o, t);
    }
    if is(
        str_of(&o, "/unansweredCallSettings/targetType"),
        "SingleTarget",
    ) && target.is_none()
    {
        o["unansweredCallSettings"]["targetType"] = json!("DoNothing");
        o["unansweredCallSettings"]["isEnabled"] = json!(false);
    }
    let immediate = fwd_on
        && is(
            str_of(&o, "/callForwardingSettings/forwardingType"),
            "Immediate",
        );
    if immediate
        && !is(fwd_type.as_deref(), "MyDelegates")
        && o["unansweredCallSettings"]["isEnabled"].as_bool() == Some(true)
    {
        o["unansweredCallSettings"]["isEnabled"] = json!(false);
    }
    if o["unansweredCallSettings"]["isEnabled"].as_bool() == Some(true) {
        clamp_forward_delay(&mut o);
    }
    if o["unansweredCallSettings"]["delaySeconds"]
        .as_u64()
        .unwrap_or(0)
        == 0
    {
        o["unansweredCallSettings"]["delaySeconds"] = json!(20);
    }
    o
}

/// Teams' `Sh`: Forward all my calls to `target_type`.
pub fn forward_all(
    current: &Value,
    target_type: &str,
    voicemail_allowed: bool,
    target: Option<&str>,
) -> Value {
    let mut o = normalized(current);
    let f = &mut o["callForwardingSettings"];
    f["forwardingType"] = json!("Immediate");
    f["targetType"] = json!(target_type);
    f["delaySeconds"] = json!(0);
    f["isEnabled"] = json!(true);
    f["target"] = if !is(Some(target_type), "Group") {
        target.map(|t| json!(t)).unwrap_or(Value::Null)
    } else {
        Value::Null
    };
    o["unansweredCallSettings"]["isEnabled"] = json!(false);
    o["unansweredCallSettings"]["safeForward"] = json!(false);
    if let Some(t) = target {
        add_favorite(&mut o, t);
    }
    if is(Some(target_type), "SingleTarget") && target.is_none() {
        o["callForwardingSettings"]["targetType"] = json!("Voicemail");
    }
    let un_type = str_of(&o, "/unansweredCallSettings/targetType").map(str::to_string);
    let un_target = str_of(&o, "/unansweredCallSettings/target").map(str::to_string);
    unanswered(
        &o,
        un_type.as_deref(),
        voicemail_allowed,
        un_target.as_deref(),
    )
}

/// Teams' `gG`: When you receive a call, also ring `target_type`
/// ("DoNothing": nobody else).
pub fn also_ring(
    current: &Value,
    target_type: Option<&str>,
    voicemail_allowed: bool,
    target: Option<&str>,
) -> Value {
    let mut o = normalized(current);
    let x = target_type
        .filter(|t| !t.is_empty())
        .unwrap_or("DoNothing")
        .to_string();
    let f = &mut o["callForwardingSettings"];
    f["forwardingType"] = json!("Simultaneous");
    f["targetType"] = json!(x);
    f["isEnabled"] = json!(!is(Some(&x), "DoNothing"));
    f["target"] = if !is(Some(&x), "Group") {
        target.map(|t| json!(t)).unwrap_or(Value::Null)
    } else {
        Value::Null
    };
    if let Some(t) = target {
        add_favorite(&mut o, t);
    }
    if is(Some(&x), "SingleTarget") && target.is_none() {
        o["callForwardingSettings"]["targetType"] = json!("DoNothing");
        o["callForwardingSettings"]["isEnabled"] = json!(false);
    }
    let un_type = str_of(&o, "/unansweredCallSettings/targetType").map(str::to_string);
    let un_target = str_of(&o, "/unansweredCallSettings/target").map(str::to_string);
    unanswered(
        &o,
        un_type.as_deref(),
        voicemail_allowed,
        un_target.as_deref(),
    )
}

/// Teams' `Ow`: ring for this many seconds before redirecting.
pub fn unanswered_delay(current: &Value, seconds: u64) -> Value {
    let mut o = normalized(current);
    o["unansweredCallSettings"]["delaySeconds"] = json!(seconds);
    clamp_forward_delay(&mut o);
    o
}

/// Teams' `Z0`: ring the also-ring target after this many seconds.
pub fn also_ring_delay(current: &Value, seconds: u64) -> Value {
    let mut o = normalized(current);
    o["callForwardingSettings"]["delaySeconds"] = json!(seconds);
    o
}

/// Turning Forward all my calls off: Teams goes back to also-ringing nobody
/// (its toggle's off path is `gG` with DoNothing).
pub fn forward_all_off(current: &Value, voicemail_allowed: bool) -> Value {
    also_ring(current, Some("DoNothing"), voicemail_allowed, None)
}

/// Teams' call group limits (Yi.YM.callForwardingSettings.callGroup).
pub const CALL_GROUP_MAX_MEMBERS: usize = 25;
pub const CALL_GROUP_IN_ORDER_MIN: usize = 2;
pub const CALL_GROUP_IN_ORDER_MAX: usize = 5;

/// Teams' `Cg`: whether the ring order can't be "inOrder" for this many
/// members (then the Ring dropdown is disabled).
pub fn call_group_order_locked(members: usize) -> bool {
    !(CALL_GROUP_IN_ORDER_MIN..=CALL_GROUP_IN_ORDER_MAX).contains(&members)
}

fn call_group_targets(o: &Value) -> Vec<String> {
    o["callGroupDetails"]["targets"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|t| t.as_str().map(str::to_string))
        .collect()
}

fn set_call_group(o: &mut Value, targets: Vec<String>) {
    // Teams' `bg`: outside 2–5 members the group rings everyone at once.
    let order = o["callGroupDetails"]["callOrder"]
        .as_str()
        .unwrap_or("simultaneous")
        .to_string();
    let order = if call_group_order_locked(targets.len()) {
        "simultaneous".to_string()
    } else {
        order
    };
    o["callGroupDetails"]["targets"] = json!(targets);
    o["callGroupDetails"]["callOrder"] = json!(order);
}

/// Calls › Call group's "Add a call group member" (settings-app `hm`):
/// the member goes last; None when the group is full or has them already.
pub fn call_group_add(current: &Value, member: &str) -> Option<Value> {
    let mut o = normalized(current);
    let mut t = call_group_targets(&o);
    if t.len() >= CALL_GROUP_MAX_MEMBERS || t.iter().any(|x| x == member) {
        return None;
    }
    t.push(member.to_string());
    set_call_group(&mut o, t);
    Some(o)
}

/// A member's Delete (settings-app `_m`'s remove).
pub fn call_group_remove(current: &Value, member: &str) -> Value {
    let mut o = normalized(current);
    let t = call_group_targets(&o)
        .into_iter()
        .filter(|x| x != member)
        .collect();
    set_call_group(&mut o, t);
    o
}

/// "Ring:" Everyone at once ("simultaneous") or In the order below
/// ("inOrder").
pub fn call_group_order(current: &Value, order: &str) -> Value {
    let mut o = normalized(current);
    o["callGroupDetails"]["callOrder"] = json!(order);
    o
}

/// Dragging a member to another place in the in-order list.
pub fn call_group_move(current: &Value, member: &str, to: usize) -> Value {
    let mut o = normalized(current);
    let mut t = call_group_targets(&o);
    if let Some(i) = t.iter().position(|x| x == member) {
        let m = t.remove(i);
        t.insert(to.min(t.len()), m);
    }
    o["callGroupDetails"]["targets"] = json!(t);
    o
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn call_group_add_and_remove_match_the_capture() {
        let base = json!({ "callForwardingSettings": { "isEnabled": false, "forwardingType": "Simultaneous", "target": null, "delaySeconds": 0 },
            "unansweredCallSettings": { "isEnabled": true, "targetType": "Voicemail", "target": null, "delaySeconds": 20, "safeForward": null },
            "callGroupDetails": { "callOrder": "simultaneous", "delaySeconds": 0, "targets": [] }, "favoriteTargets": { "targets": [] } });
        let added = call_group_add(&base, "8:orgid:b").expect("added");
        assert_eq!(
            added["callGroupDetails"],
            json!({ "callOrder": "simultaneous", "delaySeconds": 0, "targets": ["8:orgid:b"] })
        );
        assert_eq!(
            added["unansweredCallSettings"],
            base["unansweredCallSettings"]
        );
        assert!(call_group_add(&added, "8:orgid:b").is_none());
        assert_eq!(
            call_group_remove(&added, "8:orgid:b")["callGroupDetails"]["targets"],
            json!([])
        );
    }

    #[test]
    fn call_group_order_falls_back_outside_two_to_five() {
        let mut o = json!({});
        for m in ["a", "b"] {
            o = call_group_add(&o, m).unwrap();
        }
        o = call_group_order(&o, "inOrder");
        o = call_group_move(&o, "b", 0);
        assert_eq!(o["callGroupDetails"]["targets"], json!(["b", "a"]));
        assert_eq!(
            call_group_remove(&o, "a")["callGroupDetails"]["callOrder"],
            "simultaneous"
        );
        assert!(
            call_group_order_locked(1) && call_group_order_locked(6) && !call_group_order_locked(5)
        );
    }

    #[test]
    fn forward_all_to_voicemail_matches_the_capture() {
        let o = forward_all(&json!({}), "Voicemail", true, None);
        assert_eq!(
            o["callForwardingSettings"],
            json!({ "isEnabled": true, "forwardingType": "Immediate", "targetType": "Voicemail", "target": null, "delaySeconds": 0 })
        );
        assert_eq!(o["unansweredCallSettings"]["isEnabled"], false);
    }

    #[test]
    fn also_ring_a_number_keeps_it_as_a_favourite() {
        let o = also_ring(
            &json!({}),
            Some("SingleTarget"),
            true,
            Some("4:+15555550100"),
        );
        assert_eq!(o["callForwardingSettings"]["isEnabled"], true);
        assert_eq!(
            o["callForwardingSettings"]["forwardingType"],
            "Simultaneous"
        );
        assert_eq!(o["callForwardingSettings"]["target"], "4:+15555550100");
        assert_eq!(o["favoriteTargets"]["targets"][0], "4:+15555550100");
        // A number with no target falls back to ringing nobody.
        let none = also_ring(&json!({}), Some("SingleTarget"), true, None);
        assert_eq!(none["callForwardingSettings"]["isEnabled"], false);
    }

    #[test]
    fn unanswered_to_a_contact_and_delays() {
        let o = unanswered(&json!({}), Some("SingleTarget"), true, Some("8:orgid:abc"));
        assert_eq!(o["unansweredCallSettings"]["target"], "8:orgid:abc");
        assert_eq!(o["unansweredCallSettings"]["isEnabled"], true);
        let off = unanswered(&o, Some("DoNothing"), true, None);
        assert_eq!(off["unansweredCallSettings"]["isEnabled"], false);
        let d = also_ring_delay(
            &also_ring(&json!({}), Some("SingleTarget"), true, Some("4:1")),
            30,
        );
        let clamped = unanswered_delay(&d, 20);
        assert_eq!(clamped["callForwardingSettings"]["delaySeconds"], 15);
    }

    #[test]
    fn favourites_keep_three() {
        let mut o = json!({});
        for t in ["4:1", "4:2", "4:3", "4:4"] {
            o = also_ring(&o, Some("SingleTarget"), true, Some(t));
        }
        assert_eq!(
            o["favoriteTargets"]["targets"],
            json!(["4:4", "4:3", "4:2"])
        );
    }
}

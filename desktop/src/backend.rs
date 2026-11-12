//! The QML-facing backend: one QObject that drives the OST engine.
//!
//! Engine calls are async and run on a shared Tokio runtime; results are
//! posted back to the Qt thread with `qt_thread().queue`, so properties are
//! only ever written on the Qt thread. Lists cross to QML as JSON strings,
//! which QML parses into its own models; this keeps the bridge small.

use std::collections::{HashMap, HashSet};
use std::pin::Pin;
use std::sync::OnceLock;
use std::sync::atomic::{AtomicBool, Ordering};

use anyhow::Context;
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use serde_json::json;
use teams_cli::api::{self, client::TeamsClient};

/// A folder from the user's XDG user dirs (`xdg-user-dir DESKTOP`).
fn xdg_user_dir(name: &str) -> Option<std::path::PathBuf> {
    let out = std::process::Command::new("xdg-user-dir")
        .arg(name)
        .output()
        .ok()?;
    let p = String::from_utf8_lossy(&out.stdout).trim().to_string();
    (!p.is_empty()).then(|| std::path::PathBuf::from(p))
}

/// The Backend's Qt thread, so a second launch of OST (seen on another
/// thread) can ask this window to show itself.
static QT_THREAD: std::sync::OnceLock<cxx_qt::CxxQtThread<qobject::Backend>> =
    std::sync::OnceLock::new();

/// Another launch of OST asked for this window (main.rs).
pub fn request_activate() {
    if let Some(qt) = QT_THREAD.get() {
        let _ = qt.queue(|this| this.activate_requested());
    }
}

unsafe extern "C" {
    /// Put text (and its HTML form) on the clipboard (src/native.cpp).
    fn ost_set_clipboard(text: *const core::ffi::c_char, html: *const core::ffi::c_char);
    /// Put the picture in a file on the clipboard (src/native.cpp).
    fn ost_set_clipboard_image(path: *const core::ffi::c_char) -> bool;
    /// Save the clipboard's picture as a PNG (src/native.cpp).
    fn ost_save_clipboard_image(path: *const core::ffi::c_char) -> bool;
    /// Teams' taskbar badge on the window icon (src/native.cpp): the
    /// unread count, or with none, the presence glyph of `kind`.
    fn ost_set_taskbar_badge(count: i32, kind: *const core::ffi::c_char);
}
use teams_cli::calling::incoming::{ActiveCall, CallAuth, IncomingCall};
use teams_cli::calling::outgoing::{self, OutgoingCall};
use teams_cli::calling::webrtc_audio::Reoffer;

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    #[auto_cxx_name]
    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qproperty(bool, busy)]
        #[qproperty(bool, signed_in)]
        #[qproperty(QString, user_name)]
        #[qproperty(QString, user_mail)]
        #[qproperty(QString, org_name)]
        #[qproperty(QString, status_text)]
        #[qproperty(QString, chats_json)]
        #[qproperty(QString, messages_json)]
        #[qproperty(QString, current_chat_id)]
        #[qproperty(QString, current_chat_name)]
        #[qproperty(bool, has_credentials)]
        #[qproperty(QString, sign_in_code)]
        #[qproperty(QString, sign_in_url)]
        /// "", "ringing", "connecting", "connected" or "ended".
        #[qproperty(QString, call_state)]
        #[qproperty(QString, call_peer)]
        #[qproperty(QString, call_peer_id)]
        #[qproperty(bool, call_video_offered)]
        /// The Planner view last loaded: {view, plan, tasks, plans, error}.
        #[qproperty(QString, store_json)]
        /// A channel's tabs: {channel, tabs: [{id, name, app, url}], error}.
        #[qproperty(QString, channel_tabs_json)]
        /// The last tab change's outcome: {op, tab, ok} (its dialog shows
        /// Teams' failure text, or closes).
        #[qproperty(QString, channel_tab_result)]
        /// About this tab: {app, about} once loaded.
        #[qproperty(QString, app_about_json)]
        /// Teams' About dialog for an app: {app, details} or {app, error}.
        #[qproperty(QString, app_details_json)]
        /// Its reviews: {app, sort, count, reviews[], next, more} or {app, error}.
        #[qproperty(QString, app_reviews_json)]
        /// Its "More like this": {app, apps[]}.
        #[qproperty(QString, app_similar_json)]
        /// Teams' "Add agent" Store for a conversation: {conversation,
        /// loading, installed: [app], collections: [{id, title, apps}],
        /// error}.
        #[qproperty(QString, agent_store_json)]
        /// A Store page (See all, a menu entry): {id, loading | title,
        /// description, apps, sections | error}.
        #[qproperty(QString, store_page_json)]
        /// An app's App permissions (Teams' device permissions dialog):
        /// {app, name, icon, preapproved, items: [{kind, title, subtitle,
        /// on}]}.
        #[qproperty(QString, app_permissions_json)]
        /// The Store's search: {query, loading | results}.
        #[qproperty(QString, store_search_json)]
        /// The agent Store's search: {query, results: [app], loading}.
        #[qproperty(QString, agent_search_json)]
        /// The last Add: {app, conversation, busy | ok, name, bot,
        /// notificationOnly | error}.
        #[qproperty(QString, app_added_json)]
        /// The chat list's sections from the server (Teams' conversation
        /// folders): {version, folders: [{id, kind, title, sort, expanded, items}]}.
        #[qproperty(QString, folders_json)]
        /// Group chats' member counts: {chatId: n}.
        #[qproperty(QString, chat_member_counts_json)]
        /// Each team's tags by its General thread id:
        /// {threadId: [{id, name, count, mine}]}.
        #[qproperty(QString, team_tags_json)]
        /// Apps' privacy and terms links for shared app cards:
        /// {appId: {privacy, terms, name}}.
        #[qproperty(QString, app_links_json)]
        /// Share form: "" (idle), "sharing", "shared", or "error".
        #[qproperty(QString, share_state)]
        /// The last status message save: {ok, message, pinned} or {ok, error}.
        #[qproperty(QString, status_note_result)]
        /// Your status message as the presence service has it: {text,
        /// html (mentions marked), pinned}.
        #[qproperty(QString, my_note_json)]
        /// When the status you set ends (ISO UTC), or "" (Teams' "Until …"
        /// for paused notifications).
        #[qproperty(QString, my_status_ends)]
        /// The open profile card: Graph's profile with manager, reports,
        /// schedule, and presence {availability, activity, lastActive,
        /// note, outOfOffice, workLocation}; {loading} while it loads.
        #[qproperty(QString, profile_card_json)]
        /// The open chat's scheduled messages, soonest first:
        /// [{id, conversation, send_at_ms, message}].
        #[qproperty(QString, scheduled_json)]
        /// Find in chat's results: {key, loading, error, total, more,
        /// terms, hits: [{id, parent_id, sender_mri, sender_name,
        /// sender_mail, time, text, file_name, file_type, url}]}.
        #[qproperty(QString, find_json)]
        /// The search results page: {key, tab, loading, error, page:
        /// {order, terms, messages, files, images, chats, channels, people,
        /// events, …}} (api::search::Page).
        #[qproperty(QString, search_page_json)]
        /// The search page's In ▾ suggestions: {keyword, groups: [{type,
        /// items: [{name, thread, group, team, kind}]}]}.
        #[qproperty(QString, search_in_json)]
        /// Find in channel's From filter matches: {keyword, people: [{mri,
        /// name, mail}]}.
        #[qproperty(QString, find_people_json)]
        /// Settings' synced values: {props, mt, loaded}.
        #[qproperty(QString, settings_json)]
        /// The engagement-surface actions you've done (Teams' first-run
        /// tips): ["ThreadedChannelInteraction", …].
        #[qproperty(QString, esp_actions_json)]
        /// The last setting that failed to save, or "".
        #[qproperty(QString, settings_error)]
        /// Where you work today ("Office", "Remote", or "").
        #[qproperty(QString, my_work_location)]
        /// The channel threads open in windows of their own:
        /// {"<channel>;messageid=<post>": [messages, oldest first]}.
        #[qproperty(QString, thread_windows_json)]
        /// A channel menu action's outcome: {op, channel, ok, error?, data?}.
        #[qproperty(QString, channel_action_result)]
        /// New channel posts show at the top (Teams' See new posts at top;
        /// off by default).
        #[qproperty(bool, channel_posts_at_top)]
        /// The open chat has older messages to load (scroll up).
        #[qproperty(bool, messages_has_older)]
        /// Older messages are being fetched.
        #[qproperty(bool, messages_loading_older)]
        #[qproperty(bool, store_busy)]
        #[qproperty(QString, channel_files_json)]
        #[qproperty(bool, channel_files_busy)]
        #[qproperty(QString, onenote_json)]
        #[qproperty(bool, onenote_busy)]
        #[qproperty(QString, contacts_json)]
        #[qproperty(bool, contacts_busy)]
        #[qproperty(QString, planner_json)]
        #[qproperty(bool, planner_busy)]
        /// The OneDrive view last loaded: {view, drive_id, item_id, items, libraries, error}.
        #[qproperty(QString, drive_json)]
        #[qproperty(bool, drive_busy)]
        /// The current call can carry our video, and whether the camera is on.
        #[qproperty(bool, call_can_video)]
        #[qproperty(bool, call_camera_on)]
        /// The call is a Teams meeting (joined from its link).
        #[qproperty(bool, call_meeting)]
        /// The meeting's participants: [{id, name, role, active, server_muted, muted, …}].
        #[qproperty(QString, call_roster_json)]
        /// Whose camera shows where in a meeting: {mri: frame key}.
        #[qproperty(QString, call_video_json)]
        /// The meeting's dominant speaker (the media processor's history).
        #[qproperty(QString, call_speaker_mri)]
        /// Who is speaking now (Teams' voice-level outline): [mri].
        #[qproperty(QString, call_speaking_json)]
        /// The meeting has muted us.
        #[qproperty(bool, call_muted_by_meeting)]
        /// You're talking with the mic off (Teams' DeviceSpeakWhileMuted:
        /// two of the last three seconds loud while muted).
        #[qproperty(bool, call_speaking_while_muted)]
        /// Who is in the open chat's call while we aren't: [{id, name}].
        #[qproperty(QString, chat_live_roster_json)]
        /// Bumped when the meeting mutes us while we're talking (Teams'
        /// "You've been muted" alert).
        #[qproperty(i32, call_muted_remotely)]
        /// Teams' network strength for the call: "Good", "Poor" or "Bad".
        #[qproperty(QString, call_network_strength)]
        /// The meeting is locked (Teams' Lock the meeting).
        #[qproperty(bool, call_meeting_locked)]
        /// The call is a scheduled meeting joined from its link (not a
        /// chat's group call or Meet now).
        #[qproperty(bool, call_scheduled)]
        /// Held in a meeting's lobby (call_state "lobby"): someone is in
        /// the meeting, so Teams says they'll let you in shortly.
        #[qproperty(bool, call_lobby_presenter)]
        /// What attendees may not do (bits: mic 1, camera 2, chat 4).
        #[qproperty(i32, call_attendee_restrictions)]
        /// Teams' bar shows its AI indicator in this meeting.
        #[qproperty(bool, call_ai_indicator)]
        /// AI is available in the meeting (copilotMode Enabled).
        #[qproperty(bool, call_ai_available)]
        /// The meeting's Facilitator is enabled.
        #[qproperty(bool, call_ai_facilitator)]
        /// Everyone can present in the meeting (Teams then shows the
        /// meeting timer).
        #[qproperty(bool, call_everyone_presents)]
        /// The meeting's transcript (or Copilot's) runs: AI is on.
        #[qproperty(bool, call_ai_on)]
        /// Teams' recording indicator: "Transcribing", "Recording",
        /// "RecordingAndTranscribing" or "" (nothing runs).
        #[qproperty(QString, call_recording_state)]
        /// Its tooltip ("Transcription started by …").
        #[qproperty(QString, call_recording_tip)]
        /// Teams' Meeting info pane: {title, hours, schedule, location,
        /// body (HTML), canCopy}, or "" before it's loaded.
        #[qproperty(QString, call_meeting_info_json)]
        /// Why the service ended the last call when Teams shows a screen
        /// for it: "deniedFromLobby", "notAdmittedForLongTime", "removed"
        /// or "".
        #[qproperty(QString, call_end_reason)]
        /// The meeting's options as Teams' Controls menu reads them:
        /// {options: [...] (name, type, values, currentValue, isDisabled),
        /// error} or "" before they load.
        #[qproperty(QString, call_controls_json)]
        /// Names of people known only by MRI ({mri: name}), resolved on
        /// request (resolve_names), as Teams resolves a call event's author.
        #[qproperty(QString, people_names_json)]
        /// Teams' Transcript pane: [{id, kind (speech, started,
        /// stopped), userId, name, text, atMs}], oldest first.
        #[qproperty(QString, call_transcript_json)]
        /// Live captions: [{id, userId, name, text, rawText?, isFinal,
        /// atMs}], newest last (partials replaced as they're refined).
        #[qproperty(QString, call_captions_json)]
        /// You turned live captions on (the caption window shows).
        #[qproperty(bool, call_captions_on)]
        /// Call health's values: {values: {data-tid: {value, enabled}}}
        /// (call_health_refresh fills it).
        #[qproperty(QString, call_health_json)]
        /// The meeting timer (More ▸ Timer): {adhoc: Teams' timer object
        /// (remainingDuration as of lastEditMs), lastEditMs, totalMs,
        /// skewMs, sequence, live (it came in a live update), facilitator}.
        #[qproperty(QString, call_timer_json)]
        /// Real-time text is on in this call (Language and speech ▸ Turn
        /// on RTT for this call, or someone's words arrived): the captions
        /// window shows with its typing box.
        #[qproperty(bool, call_rtt_on)]
        /// You turned RTT on (its card says "enabled by you").
        #[qproperty(bool, call_rtt_initiator)]
        /// The privacy statement RTT's card links (the tenant's, else
        /// Microsoft's).
        #[qproperty(QString, call_privacy_url)]
        /// The meeting's spoken language for its captions ("en-us").
        #[qproperty(QString, call_captions_language)]
        /// Teams' calling accessibility settings (the callAccessibility
        /// user property): {startCaptionsAutomatically,
        /// profanityFilterEnabled, …}.
        #[qproperty(QString, call_accessibility_json)]
        /// More ▸ Settings ▸ Mute notifications: no message notifications
        /// for the rest of this call (calls and meetings still ring).
        #[qproperty(bool, call_notifications_muted)]
        /// More ▸ Settings ▸ Don't show chat bubbles (for this call).
        #[qproperty(bool, call_chat_bubbles_suppressed)]
        /// Bumped when the meeting is locked or unlocked while we're in it
        /// (Teams' "This meeting is locked." / "unlocked." notice).
        #[qproperty(i32, call_lock_notices)]
        /// Who presents their screen in the meeting (empty: nobody).
        #[qproperty(QString, call_share_mri)]
        /// Who waits in the meeting's lobby: [{id, name}].
        #[qproperty(QString, call_lobby_json)]
        /// Your own MRI (`8:orgid:<oid>`, lowercase), once signed in.
        #[qproperty(QString, user_mri)]
        /// The meeting's chat thread (for the call window's Chat pane).
        #[qproperty(QString, call_thread_id)]
        #[qproperty(bool, call_muted)]
        #[qproperty(bool, call_held)]
        #[qproperty(bool, call_held_by_peer)]
        #[qproperty(bool, call_can_dtmf)]
        /// We can share our screen in this call, and whether we are.
        #[qproperty(bool, call_can_share)]
        #[qproperty(bool, call_sharing)]
        #[qproperty(bool, call_hand_raised)]
        #[qproperty(QString, call_options_url)]
        #[qproperty(QString, call_chat_url)]
        /// The meeting's link to share (Teams' Share invite), once joined.
        #[qproperty(QString, call_invite_url)]
        #[qproperty(bool, call_has_audio)]
        /// "Randy Northrup is typing" for the open chat, or "".
        /// Bumped when emoticon images or the catalogue arrive.
        #[qproperty(i32, emoticons_version)]
        /// The user's Recent emoticons (Teams' roamed recentReactions, else
        /// its defaults), as a JSON array of ids.
        #[qproperty(QString, recent_reactions_json)]
        /// The preferred skin tone (Teams' preferredSkinToneIndex): 0 for
        /// none, 1 light to 5 dark.
        #[qproperty(i32, skin_tone)]
        /// The 1:1 header's call button is Video call (the last call placed
        /// from it was one; Teams' mruChatHeaderCallOption).
        #[qproperty(bool, header_call_video)]
        /// Customize reactions: "saving", "ok", "error" or empty.
        #[qproperty(QString, reaction_prefs_result)]
        /// `{message_id, total, readers: [{mri, name}]}` for Read by N of M.
        #[qproperty(QString, message_readers_json)]
        /// Teams' in-app toast: `{id, text, intent}` (intent "success" or
        /// "error"); a new id each time.
        #[qproperty(QString, toast_json)]
        /// The open chat's newest pinned message for Teams' pinned banner:
        /// `{id, sender, sender_mri, text, time, count}`, or "".
        #[qproperty(QString, pinned_json)]
        /// The last report's outcome: "", "sending", "ok" or "error".
        #[qproperty(QString, report_result)]
        /// The user's quick reactions for the hover bar (Teams' roamed
        /// defaultMessageReactions, else its default four), as a JSON array.
        #[qproperty(QString, quick_reactions_json)]
        #[qproperty(QString, typing_text)]
        /// The typer whose avatar the typing indicator shows (the latest).
        #[qproperty(QString, typing_avatar)]
        /// That typer's user id (object id), for their photo.
        #[qproperty(QString, typing_avatar_id)]
        /// Set by QML: whether the main window has focus (Teams only
        /// notifies for the open chat when it does not).
        #[qproperty(bool, window_active)]
        /// OST_SYSTEM_FRAME=1 keeps the desktop's own window frame instead
        /// of drawing Teams' title bar buttons.
        #[qproperty(bool, system_frame)]
        /// Unsent drafts, newest first: [{id, name, text, time, peerMri}].
        #[qproperty(QString, drafts_json)]
        /// The Activity feed (ActivityItem list, newest first).
        #[qproperty(QString, activity_json)]
        /// Unread Activity items, for the rail badge.
        #[qproperty(i32, activity_unread)]
        /// Settings > Appearance > Theme: "system", "light" or "dark".
        #[qproperty(QString, theme_mode)]
        /// Settings > Chats and channels > Read receipts (Teams' own
        /// per-user setting).
        #[qproperty(bool, read_receipts)]
        /// Calls history as JSON (newest first).
        #[qproperty(QString, calls_json)]
        /// Calendar events for the shown range, as JSON.
        #[qproperty(QString, calendar_json)]
        /// People search results for the new-chat picker, as JSON.
        #[qproperty(QString, people_json)]
        /// The open chat's members (Teams' roster): [{mri, name, mail, me}].
        #[qproperty(QString, chat_members_json)]
        /// The call's chat members, with presence (People pane: "People
        /// added to the chat").
        #[qproperty(QString, call_chat_members_json)]
        /// The open meeting chat's meeting: {subject, join_url, ical_uid,
        /// cancelled, start, end, organizer_id, co_organizer_ids,
        /// meeting_type}, or "" for other chats.
        #[qproperty(QString, chat_meeting_json)]
        /// Teams' Attendance view: {key, reports: [{callId, startTimeUtc,
        /// endTimeUtc, attendeeCount}], callId, report: {summary,
        /// participants}, loading, error}.
        #[qproperty(QString, attendance_json)]
        /// The meeting's lobby chat thread (Teams' organizers messaging
        /// people in the lobby), once opened; "" otherwise.
        #[qproperty(QString, call_lobby_thread)]
        /// The breakout rooms this meeting assigns us: [{name, open,
        /// join_url, auto_move, move_jitter_ms}] ("" before any).
        #[qproperty(QString, call_breakout_json)]
        /// The meeting's breakout rooms as their organizer manages them:
        /// {rooms: [{name, thread, join_url, open, participants: [{mri,
        /// role}]}], settings: {allow_select, room_duration, allow_return,
        /// auto_move}, loaded} ("" before any).
        #[qproperty(QString, call_breakout_rooms_json)]
        /// The meeting's rooms from the call (its organizer's view):
        /// [{name, thread, join_url, open, invitees, auto_move,
        /// allow_return}] ("" before any).
        #[qproperty(QString, call_breakout_all_json)]
        /// The breakout room this call is: {closed, allow_return,
        /// main_join_url, move_jitter_ms} ("" in a main meeting).
        #[qproperty(QString, call_breakout_room_json)]
        /// The main meeting on hold while you're in one of its breakout
        /// rooms as its organizer: {title, url, since} ("" when none).
        #[qproperty(QString, call_held_meeting_json)]
        /// The fun picker's GIF results: {query, items: [{url, preview,
        /// width, height, title}], error}.
        #[qproperty(QString, fun_results_json)]
        /// The org's custom emoji: [{id, shortcut, document_id, creator,
        /// created_on, creator_name}], newest first.
        #[qproperty(QString, custom_emoji_json)]
        /// The Add emoji dialog's outcome: "" | "adding" | "ok" |
        /// "duplicate" | "limit:{n}" | "error".
        #[qproperty(QString, custom_emoji_result)]
        /// Your messaging policy lets you add / delete custom emoji
        /// (createCustomEmojis / deleteCustomEmojis).
        #[qproperty(bool, custom_emoji_can_add)]
        #[qproperty(bool, custom_emoji_can_delete)]
        /// Joined teams and their channels, as JSON.
        #[qproperty(QString, teams_json)]
        type Backend = super::BackendRust;
    }

    #[auto_cxx_name]
    extern "RustQt" {
        /// Load the signed-in user and the chat list.
        #[qinvokable]
        fn refresh(self: Pin<&mut Backend>);

        /// Decide what to show at startup: the app, or the sign-in screen.
        #[qinvokable]
        fn start(self: Pin<&mut Backend>);

        /// Begin a device-code sign-in; the code and page appear in
        /// `signInCode` / `signInUrl`, and the app loads once approved.
        #[qinvokable]
        fn begin_sign_in(self: Pin<&mut Backend>);

        /// Forget the stored credentials and return to the sign-in screen.
        #[qinvokable]
        fn sign_out(self: Pin<&mut Backend>);

        /// Open a chat and load its messages.
        #[qinvokable]
        fn select_chat(self: Pin<&mut Backend>, chat_id: &QString, chat_name: &QString);

        /// Send a message to the open chat, then reload it.
        #[qinvokable]
        fn send_message(self: Pin<&mut Backend>, text: &QString);
        /// Quote a message in the next send (Teams' Reply with quote):
        /// `{message_id, sender_mri, sender_name, preview}`, or "" to drop it.
        #[qinvokable]
        fn set_reply_quote(self: Pin<&mut Backend>, quote_json: &QString);

        /// The next message's delivery option: "", "high" or "urgent".
        #[qinvokable]
        fn set_next_importance(self: Pin<&mut Backend>, importance: &QString);
        /// The next channel post's fields from Teams' post composer:
        /// {"subject", "title", "theme"} (theme "0".."11" for an
        /// announcement, "" otherwise); "" clears them.
        #[qinvokable]
        fn set_next_post(self: Pin<&mut Backend>, post_json: &QString);
        /// The next message sent from the compose is scheduled for `ms`
        /// (epoch ms; "" for none), as Teams' Schedule message.
        #[qinvokable]
        fn set_next_schedule(self: Pin<&mut Backend>, ms: &QString);
        /// Cancel a scheduled message (Teams' Delete on it).
        #[qinvokable]
        fn cancel_scheduled(self: Pin<&mut Backend>, id: &QString);
        /// Search a chat or channel as Teams' Find in chat: `filters_json`
        /// is {files, start, end, attachment, mentions, from_mail,
        /// from_oid}; `from` the first result (25 a page, appended).
        /// Results land in find_json under `key`.
        #[qinvokable]
        fn find_in_chat(self: Pin<&mut Backend>, key: &QString, thread: &QString, keywords: &QString, filters_json: &QString, from: i32);
        /// A Find in chat file result's ··· action: "download" or
        /// "favorite" (Teams' Download and Favorite), by its address.
        #[qinvokable]
        fn find_file_action(self: Pin<&mut Backend>, op: &QString, url: &QString);
        /// Search as Teams' results page: `tab` (api::search::TABS),
        /// `filters_json` (api::search::Filters); `from` pages Messages and
        /// Files (appended). Results land in search_page_json under `key`.
        #[qinvokable]
        fn search_page(self: Pin<&mut Backend>, key: &QString, tab: &QString, keywords: &QString, filters_json: &QString, from: i32);
        /// In ▾'s suggestions (chats, channels, teams) for `keyword`.
        #[qinvokable]
        fn search_in_suggest(self: Pin<&mut Backend>, keyword: &QString);
        /// Find in channel's From filter: the channel's people matching
        /// `keyword`, into find_people_json ([{mri, name, mail}]).
        #[qinvokable]
        fn find_people(self: Pin<&mut Backend>, channel: &QString, keyword: &QString);
        /// Feedback (Report a problem / Give a compliment): the repo's new
        /// issue form filled in from `report_json` ({kind, text, area,
        /// context, share_logs, contact, files}); the first picture goes on
        /// the clipboard to paste into it.
        #[qinvokable]
        fn feedback_issue_url(self: Pin<&mut Backend>, report_json: &QString) -> QString;
        /// The feedback repo's pages: "ideas" (Suggest a feature), "privacy",
        /// "privacy-feedback", "repo".
        #[qinvokable]
        fn feedback_link(self: &Backend, which: &QString) -> QString;
        /// A folder for a feedback report's screenshots and files (created).
        #[qinvokable]
        fn feedback_dir(self: &Backend) -> QString;
        /// Help (F1): the categories with their articles (docs/help):
        /// [{id, title, description, articles: [{id, category, title,
        /// description, featured, body}]}].
        #[qinvokable]
        fn help_library(self: &Backend) -> QString;
        /// Help's search: the matching articles, best first.
        #[qinvokable]
        fn help_search(self: &Backend, query: &QString) -> QString;
        /// Open the feedback form from any window (feedback_requested).
        #[qinvokable]
        fn request_feedback(self: Pin<&mut Backend>, kind: &QString, area: &QString, context: &QString);
        /// Paste the clipboard's picture into `dir`; its path, or "".
        #[qinvokable]
        fn paste_clipboard_image(self: &Backend, dir: &QString) -> QString;
        /// Save an edited scheduled message (its text, media and time).
        #[qinvokable]
        fn edit_scheduled(
            self: Pin<&mut Backend>,
            id: &QString,
            client_message_id: &QString,
            editor_html: &QString,
            media_json: &QString,
            send_at_ms: &QString,
        );
        /// Copy a message's link as Teams does (text: the URL; HTML: Teams'
        /// copy-link anchor). `message_json`: {id, sender, text, root_id};
        /// `place_json`: {team_id, team_name, channel_name} for a channel.
        #[qinvokable]
        fn copy_message_link(self: &Backend, message_json: &QString, place_json: &QString);

        /// Copy the open chat's link as Teams does (rich text named after
        /// the chat), with Teams' toast.
        #[qinvokable]
        fn copy_chat_link(self: Pin<&mut Backend>);

        /// Rename the open group chat (Teams' Name group chat).
        #[qinvokable]
        fn rename_chat(self: Pin<&mut Backend>, topic: &QString);

        /// The chat list's Mark as read / Mark as unread for any chat.
        #[qinvokable]
        fn set_chat_unread(self: Pin<&mut Backend>, chat_id: &QString, unread: bool);

        /// Copy a chat's link (Teams' Copy link), from its menu in the list.
        #[qinvokable]
        fn copy_link_of_chat(self: Pin<&mut Backend>, chat_id: &QString, chat_name: &QString);

        /// A custom emoji's picture URL as messages carry it (the asyncgw
        /// imgt2_anim view).
        #[qinvokable]
        fn custom_emoji_send_url(self: &Backend, document_id: &QString) -> QString;

        /// Load the org's custom emoji into customEmojiJson.
        #[qinvokable]
        fn load_custom_emoji(self: Pin<&mut Backend>);

        /// Add a custom emoji for the org from a picture file (Teams' Add
        /// emoji); the outcome lands in customEmojiResult.
        #[qinvokable]
        fn add_custom_emoji(self: Pin<&mut Backend>, name: &QString, path: &QString);

        /// Delete a custom emoji for the org (by its "{name};{documentId}").
        #[qinvokable]
        fn delete_custom_emoji(self: Pin<&mut Backend>, id: &QString);

        /// Search GIFs for the fun picker; an empty query is GIPHY's
        /// trending list. The result lands in funResultsJson.
        #[qinvokable]
        fn search_gifs(self: Pin<&mut Backend>, query: &QString);

        /// Mute or unmute a chat (Teams' Mute / Unmute).
        #[qinvokable]
        fn set_chat_muted(self: Pin<&mut Backend>, chat_id: &QString, muted: bool);
        /// Add people (`mris_json`, a JSON array of MRIs) to the open group
        /// chat with Teams' history choice: `days` < 0 none, 0 all, else
        /// the past `days` days. The roster reloads after.
        #[qinvokable]
        fn add_chat_members(self: Pin<&mut Backend>, mris_json: &QString, days: i32);
        /// Put text on the clipboard (a code block's Copy) and say so.
        #[qinvokable]
        fn copy_text(self: Pin<&mut Backend>, text: &QString);
        /// Remove someone from the open group chat; the roster reloads after.
        #[qinvokable]
        fn remove_chat_member(self: Pin<&mut Backend>, mri: &QString);
        /// Save or unsave a message (Teams' Save this message).
        #[qinvokable]
        fn set_message_saved(self: Pin<&mut Backend>, message_id: &QString, save: bool);
        /// Mark a message unread (Teams' bookmark behind the horizon).
        #[qinvokable]
        fn mark_message_unread(
            self: Pin<&mut Backend>,
            message_id: &QString,
            client_message_id: &QString,
        );
        /// Pin or unpin a message for everyone.
        #[qinvokable]
        fn set_message_pinned(self: Pin<&mut Backend>, message_id: &QString, pin: bool);
        /// Load who has read one of your messages into messageReadersJson.
        #[qinvokable]
        fn load_message_readers(self: Pin<&mut Backend>, message_id: &QString);
        /// Forward a message of the open chat (Teams' Forward): `targets_json`
        /// `[{kind: "person", oid, name} | {kind: "chat", id}]`, an optional
        /// note. The outcome lands in toastJson.
        #[qinvokable]
        fn forward_message(
            self: Pin<&mut Backend>,
            message_id: &QString,
            targets_json: &QString,
            note: &QString,
        );
        /// Report someone's message as a security concern (Teams' Report this
        /// message); the outcome lands in reportResult ("ok" or "error").
        #[qinvokable]
        fn report_message(self: Pin<&mut Backend>, message_id: &QString, comment: &QString);
        /// Report the meeting we're in as a security concern (More ▸
        /// Report a concern), naming the chosen participants (a JSON list
        /// of MRIs); the outcome comes back in report_result.
        #[qinvokable]
        fn report_meeting(self: Pin<&mut Backend>, comment: &QString, reported_json: &QString);
        /// Set where you work today ("Office", "Remote", or "" to clear),
        /// as Teams' Set work location.
        #[qinvokable]
        fn set_work_location_today(self: Pin<&mut Backend>, location: &QString);
        /// A meeting chat's Report a concern (its thread and meeting, no
        /// call).
        #[qinvokable]
        fn report_meeting_chat(self: Pin<&mut Backend>, thread: &QString, ical_uid: &QString, comment: &QString, reported_json: &QString);
        /// Translate a message (Teams' Translate) or show its original.
        #[qinvokable]
        fn translate_message(self: Pin<&mut Backend>, message_id: &QString, on: bool);
        /// Retry a failed message, by its clientmessageid.
        #[qinvokable]
        fn retry_failed_message(self: Pin<&mut Backend>, client_message_id: &QString);
        /// Delete a failed message (local only, as Teams).
        #[qinvokable]
        fn delete_failed_message(self: Pin<&mut Backend>, client_message_id: &QString);

        /// Answer the ringing call, with or without video.
        #[qinvokable]
        fn accept_call(self: Pin<&mut Backend>, with_video: bool);

        /// Decline the ringing call.
        #[qinvokable]
        fn decline_call(self: Pin<&mut Backend>);

        /// Call the other person in the open 1:1 chat.
        #[qinvokable]
        fn start_call(self: Pin<&mut Backend>);

        /// Video call the other person in the open 1:1 chat: the call starts
        /// with the camera on.
        #[qinvokable]
        fn start_video_call(self: Pin<&mut Backend>);

        /// Group chats: Teams' Meet now (a huddle; members are nudged).
        #[qinvokable]
        fn meet_now(self: Pin<&mut Backend>);
        /// Channels: Teams' Meet now, a new meeting in the channel with
        /// this title (from the pre-join's title field).
        #[qinvokable]
        fn channel_meet_now(self: Pin<&mut Backend>, channel_id: &QString, title: &QString);

        /// Group chats: join the chat's ongoing call (Teams' Join).
        #[qinvokable]
        fn join_group_call(self: Pin<&mut Backend>);
        /// Watch the open chat's call without joining (its live roster), or
        /// stop (empty thread).
        #[qinvokable]
        fn watch_chat_call(
            self: Pin<&mut Backend>,
            thread_id: &QString,
            conversation_url: &QString,
            call_id: &QString,
        );

        /// Join the Teams meeting with this join link; `title` is shown in
        /// the call window.
        #[qinvokable]
        fn join_meeting(self: Pin<&mut Backend>, join_url: &QString, title: &QString);
        /// Teams' Controls menu: read the meeting's options (lobby,
        /// presenters, chat, attendee restrictions) into
        /// call_controls_json.
        #[qinvokable]
        fn load_meeting_controls(self: Pin<&mut Backend>);
        /// Save one meeting option (Teams' Controls items and Meeting
        /// options' Apply), then read the options again.
        #[qinvokable]
        fn set_meeting_option(self: Pin<&mut Backend>, name: &QString, value_json: &QString);
        /// Teams' Meeting options Apply: save several options
        /// ({name: value}) at once.
        #[qinvokable]
        fn set_meeting_options(self: Pin<&mut Backend>, changes_json: &QString);
        /// Resolve these MRIs' names (a JSON list) into people_names_json.
        #[qinvokable]
        fn resolve_names(self: Pin<&mut Backend>, mris_json: &QString);
        /// Teams' Rejoin on its retry screen: join the meeting last joined
        /// again.
        #[qinvokable]
        fn rejoin_meeting(self: Pin<&mut Backend>);

        /// End the current call.
        #[qinvokable]
        fn hang_up(self: Pin<&mut Backend>);
        /// Teams' "Leave on all my devices".
        #[qinvokable]
        fn leave_on_all_devices(self: Pin<&mut Backend>);
        /// A meeting participant's ··· menu: "mute", "spotlight",
        /// "unspotlight", "attendee", "presenter" or "remove".
        #[qinvokable]
        fn participant_action(
            self: Pin<&mut Backend>,
            action: &QString,
            id: &QString,
            name: &QString,
            state_id: &QString,
        );
        /// End the meeting for everyone (organizers; Teams' End meeting).
        #[qinvokable]
        fn end_meeting(self: Pin<&mut Backend>);
        /// Mute everyone else in the meeting (Teams' Mute all).
        #[qinvokable]
        fn mute_all(self: Pin<&mut Backend>);
        /// The People pane's More actions: "lock", "unlock", "lowerHands"
        /// or "stopSpotlights".
        #[qinvokable]
        fn meeting_action(self: Pin<&mut Backend>, action: &QString);
        /// Disable or allow mic and camera for attendees: the restriction
        /// bits to set (mic 1, camera 2).
        #[qinvokable]
        fn set_attendee_restrictions(self: Pin<&mut Backend>, bits: i32);
        /// Save the attendance list to Downloads (Teams' Download
        /// attendance list).
        #[qinvokable]
        fn download_attendance_list(self: Pin<&mut Backend>);
        /// Teams' Attendance view: the meeting's reports (history) and one
        /// report into attendance_json (`call_id` empty: the newest).
        /// `message` is a channel meeting's post id, else empty.
        #[qinvokable]
        fn load_attendance(
            self: Pin<&mut Backend>,
            thread: &QString,
            organizer: &QString,
            message: &QString,
            call_id: &QString,
        );
        /// Teams' lobby chat: get (or create) the meeting's lobby chat
        /// thread into call_lobby_thread.
        #[qinvokable]
        fn open_lobby_chat(self: Pin<&mut Backend>);
        /// Breakout rooms: leave this meeting quietly and join another (a
        /// room, or the main meeting again).
        #[qinvokable]
        fn move_meeting(self: Pin<&mut Backend>, join_url: &QString, title: &QString);
        /// The meeting last joined: {url, title}.
        #[qinvokable]
        fn current_meeting(self: Pin<&mut Backend>) -> QString;
        /// Teams' Join on a breakout room's menu: put the main meeting on
        /// hold and join the room.
        #[qinvokable]
        fn join_room_holding_main(self: Pin<&mut Backend>, join_url: &QString, title: &QString);
        /// Leave the breakout room joined over a held main meeting: back to
        /// the main meeting (`resume`, Teams' Leave room and Resume) or out
        /// of both (Leave meeting).
        #[qinvokable]
        fn leave_room(self: Pin<&mut Backend>, resume: bool);
        /// Leave the held main meeting, staying in the room (Teams' Leave
        /// in the held meeting's window).
        #[qinvokable]
        fn leave_held_meeting(self: Pin<&mut Backend>);
        /// Manage the meeting's breakout rooms as Teams' organizers do:
        /// "refresh"; "create" {rooms: [{name, participants}], settings};
        /// "assign" {rooms: [{thread, name, participants}], total};
        /// "open" / "close" {threads (all when empty), total}; "settings"
        /// {allow_select, room_duration, allow_return, auto_move}; "add"
        /// {name}; "rename" {thread, name}; "delete" {thread};
        /// "delete_all"; "announce" {message}. The rooms come back in
        /// call_breakout_rooms_json; breakout_action_done says how it went.
        #[qinvokable]
        fn breakout_action(self: Pin<&mut Backend>, action: &QString, args_json: &QString);
        /// OneDrive's share dialog (docs/spec/onedrive-share.md) for a file
        /// ({site, list, item}): "info"; "people" {query}; "send" {people,
        /// edit, message}; "link" {scope, edit, expiration, password} (its
        /// address); "role" {login, role}; "unlink" {kind, share_id};
        /// "stop" (Stop sharing); for Teams' "Share this file": "recipients"
        /// {query}, "access" {upns}, "post" {targets, note, file: {name,
        /// object_url, share_url, share_id}}. The
        /// answer comes back in share_done.
        #[qinvokable]
        fn share_action(self: Pin<&mut Backend>, op: &QString, item_json: &QString, args_json: &QString);
        /// Teams' Download in the Attendance view: save the report file
        /// (the service's name) to Downloads.
        #[qinvokable]
        fn download_attendance_report(
            self: Pin<&mut Backend>,
            thread: &QString,
            organizer: &QString,
            call_id: &QString,
        );
        /// Teams' Record and transcribe: "startTranscription",
        /// "stopTranscription", "startRecording" (recording only when the
        /// transcript runs) or "stopRecording", in `language` ("en-us"),
        /// `audio_only` for "Audio only". A failure comes back as
        /// meeting_action_failed(command).
        #[qinvokable]
        fn recorder_command(self: Pin<&mut Backend>, command: &QString, language: &QString, audio_only: bool);
        /// Turn live captions on or off for you, as Teams does: on asks the
        /// meeting's recorder for captions (unless they run already) and
        /// then says so in our endpoint metadata; off only says so.
        #[qinvokable]
        fn set_captions(self: Pin<&mut Backend>, on: bool);
        /// Set the meeting's spoken language ("de-de") for its captions.
        #[qinvokable]
        fn set_captions_language(self: Pin<&mut Backend>, language: &QString);
        /// Change the meeting's ad-hoc timer for everyone: "start",
        /// "pause", "resume", "reset", "cancel" (the popover's),
        /// "cancelOverTime", "startWith" (`arg` ms) or "add" (`arg`
        /// minutes). It changes when the meeting's update comes back.
        #[qinvokable]
        fn meeting_timer(self: Pin<&mut Backend>, action: &QString, arg: i32);
        /// The timer ran out: Teams' chime.
        #[qinvokable]
        fn timer_chime(self: &Backend);
        /// Recompute Call health's values from the last 15 seconds (Teams
        /// refreshes the open pane every 15 s, and at once when media
        /// turns on).
        #[qinvokable]
        fn call_health_refresh(self: Pin<&mut Backend>);
        /// Turn real-time text on for this call (after Teams' "RTT
        /// (real-time text) will be turned on for everyone in the call.").
        #[qinvokable]
        fn start_rtt(self: Pin<&mut Backend>);
        /// The RTT box now says `text`: what changed waits for the next
        /// rtt_flush (Teams sends every 300 ms). False past 2000
        /// characters (the box keeps what it had; Teams says "You cannot
        /// type more than 2000 characters").
        #[qinvokable]
        fn rtt_input(self: Pin<&mut Backend>, text: &QString) -> bool;
        /// Send what was typed since the last flush; true when something
        /// went.
        #[qinvokable]
        fn rtt_flush(self: Pin<&mut Backend>) -> bool;
        /// End the line: Enter (`manual`), or 3 s without a key. Returns
        /// false when Enter found only spaces (Teams then says "Please type
        /// a message to continue." and sends nothing). The box empties.
        #[qinvokable]
        fn rtt_commit(self: Pin<&mut Backend>, manual: bool) -> bool;
        /// Change calling accessibility settings (a JSON patch such as
        /// {"profanityFilterEnabled": true}), saved as Teams saves them.
        #[qinvokable]
        fn update_call_accessibility(self: Pin<&mut Backend>, patch: &QString);
        /// Read the meeting's stored transcript into call_transcript_json
        /// (Teams does on opening the Transcript pane).
        #[qinvokable]
        fn load_transcript(self: Pin<&mut Backend>);
        /// Fill call_meeting_info_json for Teams' Meeting info pane.
        #[qinvokable]
        fn load_meeting_info(self: Pin<&mut Backend>);
        /// Teams' "Copy join info": the meeting's invitation, as HTML and
        /// text.
        #[qinvokable]
        fn copy_meeting_join_info(self: Pin<&mut Backend>);
        /// Teams' "Turn off other videos": stop (or resume) asking for
        /// others' cameras.
        #[qinvokable]
        fn set_incoming_video(self: Pin<&mut Backend>, on: bool);
        /// How wide each tile is drawn: {mri: px} (Teams asks for video to
        /// fit its tiles).
        #[qinvokable]
        fn set_video_widths(self: Pin<&mut Backend>, json: &QString);
        /// Send a meeting reaction: like, heart, applause, laugh, surprised.
        #[qinvokable]
        fn send_reaction(self: Pin<&mut Backend>, name: &QString);

        /// Load calendar events between two UTC instants (ISO 8601).
        #[qinvokable]
        fn load_calendar(self: Pin<&mut Backend>, start_utc: &QString, end_utc: &QString);

        /// The window gained focus: mark the open chat read.
        #[qinvokable]
        fn mark_current_read(self: Pin<&mut Backend>);

        /// Re-check how far the other person has read the open chat, and
        /// update the Seen marks.
        #[qinvokable]
        fn refresh_receipts(self: Pin<&mut Backend>);

        /// Search the directory for the new-chat picker.
        #[qinvokable]
        fn search_people(self: Pin<&mut Backend>, query: &QString);
        /// As search_people, with you among the results (the status
        /// message picker).
        #[qinvokable]
        fn search_people_with_me(self: Pin<&mut Backend>, query: &QString);

        /// Open (or start) the 1:1 chat with a person by object id.
        #[qinvokable]
        fn open_chat_with(self: Pin<&mut Backend>, oid: &QString, name: &QString);

        /// Load the Calls history.
        #[qinvokable]
        fn load_calls(self: Pin<&mut Backend>);

        /// Add or remove our reaction on a message in the open chat.
        #[qinvokable]
        fn toggle_reaction(self: Pin<&mut Backend>, message_id: &QString, key: &QString, on: bool);

        /// Replace the text of one of our messages in the open chat.
        #[qinvokable]
        fn edit_message(self: Pin<&mut Backend>, message_id: &QString, text: &QString);

        /// Follow or unfollow a channel thread (Teams' Follow thread).
        #[qinvokable]
        fn set_thread_following(self: Pin<&mut Backend>, root_id: &QString, follow: bool);
        /// A Threads-layout thread's read state in the open channel, as
        /// Teams changes it: `change` "read" (to `newest_reply`), "clear"
        /// (the Mark as unread bookmark) or "unread" (from `newest_reply`).
        #[qinvokable]
        fn set_thread_read(self: Pin<&mut Backend>, root_id: &QString, change: &QString, newest_reply: &QString);

        /// Edit one of our messages in place, as Teams does: the editor's
        /// rich text (formatting kept) and the quote it keeps (JSON, or
        /// empty for none).
        #[qinvokable]
        fn edit_message_rich(
            self: Pin<&mut Backend>,
            message_id: &QString,
            editor_html: &QString,
            quote_json: &QString,
            media_json: &QString,
        );

        /// Delete one of our messages in the open chat.
        #[qinvokable]
        fn delete_message(self: Pin<&mut Backend>, message_id: &QString);
        /// Undo a delete made in this session.
        #[qinvokable]
        fn undo_delete_message(self: Pin<&mut Backend>, message_id: &QString);

        /// Ring (or stop ringing) for an incoming call.
        #[qinvokable]
        fn set_ringer(self: Pin<&mut Backend>, on: bool);

        /// The user is typing in the open chat; tells the others (at most
        /// every few seconds).
        #[qinvokable]
        fn user_typing(self: Pin<&mut Backend>);

        /// Mute or unmute the microphone in the current call.
        #[qinvokable]
        fn toggle_mute(self: Pin<&mut Backend>);

        /// Turn the camera on or off in the current call.
        #[qinvokable]
        fn toggle_camera(self: Pin<&mut Backend>);
        /// Pre-join: show your camera as the "self" preview, or stop.
        /// False when the camera can't be opened.
        #[qinvokable]
        fn set_camera_preview(self: Pin<&mut Backend>, on: bool) -> bool;
        /// The cameras: JSON {devices: [{path, name}], current: path}.
        #[qinvokable]
        fn video_devices(self: Pin<&mut Backend>) -> QString;
        /// Use this camera (a V4L2 path), switching a running call's camera
        /// to it at once.
        #[qinvokable]
        fn set_camera_device(self: Pin<&mut Backend>, path: &QString);

        /// Put the call on hold, or resume it.
        #[qinvokable]
        fn toggle_hold(self: Pin<&mut Backend>);

        /// Share your screen (the desktop's picker asks what), or stop.
        #[qinvokable]
        fn toggle_share(self: Pin<&mut Backend>);

        /// "Don't use audio": no sound sent or played in this call.
        #[qinvokable]
        fn use_no_audio(self: Pin<&mut Backend>);

        /// Raise or lower your hand in the meeting.
        #[qinvokable]
        fn toggle_hand(self: Pin<&mut Backend>);
        /// Admit someone waiting in the lobby (Teams' Admit); `not_bot`:
        /// "This isn't a bot" was ticked for a suspected guest.
        #[qinvokable]
        fn admit_from_lobby(self: Pin<&mut Backend>, id: &QString, name: &QString, not_bot: bool);
        /// Admit everyone in the lobby (Teams' Admit all).
        #[qinvokable]
        fn admit_all_from_lobby(self: Pin<&mut Backend>);
        /// Deny someone waiting in the lobby (Teams' Deny).
        #[qinvokable]
        fn deny_from_lobby(self: Pin<&mut Backend>, id: &QString, name: &QString);

        /// Transfer the call to a person (AAD object id).
        #[qinvokable]
        fn transfer_call(self: Pin<&mut Backend>, oid: &QString);

        /// Send a dial-pad key (0-9, *, #) as a tone in the call.
        #[qinvokable]
        fn send_dtmf(self: Pin<&mut Backend>, key: &QString);
    }

    #[auto_cxx_name]
    extern "RustQt" {
        /// A notification was clicked: bring the window forward.
        #[qsignal]
        fn activate_requested(self: Pin<&mut Backend>);

        /// Some window asked for Feedback (Report a problem / Give a
        /// compliment): the main window opens the form.
        #[qsignal]
        fn feedback_requested(self: Pin<&mut Backend>, kind: QString, area: QString, context: QString);

        /// A profile or team picture asked for with photo_for is ready.
        #[qsignal]
        fn photo_ready(self: Pin<&mut Backend>, id: QString);

        /// A file's preview picture asked for with file_thumbnail is ready.
        #[qsignal]
        fn thumbnail_ready(self: Pin<&mut Backend>, url: QString);

        /// A share_action finished: its op, its result (JSON) and an error.
        #[qsignal]
        fn share_done(self: Pin<&mut Backend>, op: QString, result: QString, error: QString);

        /// A drive_action finished: its op, its result (JSON) and an error.
        #[qsignal]
        fn drive_action_done(self: Pin<&mut Backend>, op: QString, result: QString, error: QString);

        /// Someone in the meeting reacted (Teams' meeting reactions):
        /// their MRI and the reaction's name.
        #[qsignal]
        fn meeting_reaction(self: Pin<&mut Backend>, mri: QString, name: QString);
        /// A chat message in the call's chat from someone else (Teams'
        /// chat bubble): their MRI, name and the message's text.
        #[qsignal]
        fn chat_bubble(self: Pin<&mut Backend>, mri: QString, name: QString, text: QString);
        /// You typed RTT on another of your devices: Teams empties this
        /// device's RTT box.
        #[qsignal]
        fn rtt_input_cleared(self: Pin<&mut Backend>);
        /// A More actions request failed ("lock" or "unlock": Teams offers
        /// Try again).
        #[qsignal]
        fn meeting_action_failed(self: Pin<&mut Backend>, action: QString);
        /// A breakout rooms action finished: `error` is empty when it
        /// worked.
        #[qsignal]
        fn breakout_action_done(self: Pin<&mut Backend>, action: QString, error: QString);
        /// The tray asks for the window (its icon or the name row).
        #[qsignal]
        fn tray_show(self: Pin<&mut Backend>);
        /// The tray's Quit OST.
        #[qsignal]
        fn tray_quit(self: Pin<&mut Backend>);
        /// Show the tray icon (first call) and keep its badge and menu
        /// current: presence kind, the status label, "Name | Organisation".
        #[qinvokable]
        fn update_tray(
            self: Pin<&mut Backend>,
            kind: &QString,
            status_label: &QString,
            name_line: &QString,
        );

        /// The picture for "me", a user ("8:orgid:<oid>" or "<oid>") or a
        /// team ("team:<group id>"): a file URL, or "" for initials. Starts
        /// a download when needed and signals photo_ready when it lands.
        #[qinvokable]
        fn photo_for(self: Pin<&mut Backend>, id: &QString, name: &QString) -> QString;

        /// A file's preview picture, as Teams' search file cards show it
        /// (from its link): a file URL, or "" while it downloads (then
        /// thumbnail_ready) or when the file has none.
        #[qinvokable]
        fn file_thumbnail(self: Pin<&mut Backend>, url: &QString) -> QString;

        /// Teams' image for an emoticon or reaction key (`like`,
        /// `heart-tone2`, `1f603_…`) at one of Teams' asset sizes: a file URL,
        /// or "" until it has downloaded (emoticonsVersion then changes).
        #[qinvokable]
        fn emoticon_url(self: Pin<&mut Backend>, key: &QString, size: i32) -> QString;

        /// An emoticon's unicode character (its alt text when sent), or "".
        #[qinvokable]
        fn emoticon_unicode(self: &Backend, key: &QString) -> QString;

        /// A card image as a local file URL once downloaded (empty until
        /// then; emoticonsVersion changes when it lands).
        #[qinvokable]
        fn card_image(self: Pin<&mut Backend>, url: &QString) -> QString;
        /// Teams' Noise suppression switch (Mic ▾): on or off, kept.
        #[qinvokable]
        fn set_noise_suppression(self: Pin<&mut Backend>, on: bool);
        /// Teams' High fidelity music mode ("musicMode") and its "Enable
        /// echo cancellation" ("musicModeEcho"): saved and applied to the
        /// call's audio at once.
        #[qinvokable]
        fn set_music_mode(self: Pin<&mut Backend>, on: bool, echo_cancellation: bool);
        /// Teams' taskbar badge: the app bar's unread total on the window
        /// icon, else your presence glyph (kind as the tray's).
        #[qinvokable]
        fn set_taskbar_badge(self: &Backend, count: i32, kind: &QString);
        /// The call bar as Teams builds it from its layout config: `facts`
        /// (JSON, see teams_cli::calling::ubar::Facts), each control's
        /// width (JSON {name: px}), a divider's width and the middle slot's
        /// room. Returns JSON {bar, end, overflowed, more, onHold}.
        #[qinvokable]
        fn ubar_arrange(
            self: &Backend,
            facts: &QString,
            widths: &QString,
            divider: f64,
            available: f64,
        ) -> QString;
        /// A picker category's icon (Teams' 20 x 40 single-colour sprite):
        /// a file URL, or "" until it has downloaded.
        #[qinvokable]
        fn emoticon_category_icon(self: Pin<&mut Backend>, category_id: &QString) -> QString;
        /// Teams' emoticon catalogue for the picker, as JSON
        /// `[{title, emoticons: [{id, description, diverse}]}]`; "" until
        /// loaded (emoticonsVersion then changes).
        #[qinvokable]
        fn emoticon_catalog_json(self: Pin<&mut Backend>) -> QString;
        /// A reaction's name as Teams shows it ("Like", or the emoticon's
        /// description).
        #[qinvokable]
        fn emoticon_name(self: &Backend, key: &QString) -> QString;

        /// An emoticon id in the preferred skin tone when it has tones
        /// (`{id}-tone{n}`), else the id.
        #[qinvokable]
        fn emoticon_toned(self: &Backend, key: &QString) -> QString;

        /// An emoticon id in a given skin tone when it has tones.
        #[qinvokable]
        fn emoticon_in_tone(self: &Backend, key: &QString, tone: i32) -> QString;

        /// Save the quick reactions (client ids, JSON) and the skin tone.
        #[qinvokable]
        fn save_reaction_prefs(self: Pin<&mut Backend>, slots_json: &QString, tone: i32);
        /// Teams' asset size for a named emoticon size ("medium", "small"…)
        /// on this screen.
        #[qinvokable]
        fn emoticon_size(self: &Backend, named: &QString, hidpi: bool) -> i32;

        /// Keep (or, when empty, drop) the unsent text for a chat.
        #[qinvokable]
        fn set_draft(self: Pin<&mut Backend>, chat_id: &QString, text: &QString);

        /// The unsent text kept for a chat, or "".
        #[qinvokable]
        fn draft_for(self: Pin<&mut Backend>, chat_id: &QString) -> QString;

        /// Load the Activity feed.
        #[qinvokable]
        fn load_activity(self: Pin<&mut Backend>);

        /// The Activity view is showing: mark the feed read, as Teams does.
        #[qinvokable]
        fn mark_activity_read(self: Pin<&mut Backend>);

        /// An Activity item was opened: it stops being bold.
        #[qinvokable]
        fn mark_activity_item_read(self: Pin<&mut Backend>, id: &QString);

        /// A saved app setting ("" when unset).
        #[qinvokable]
        fn setting(self: Pin<&mut Backend>, name: &QString) -> QString;
        /// Your tenant's id (web apps Teams embeds are told it).
        #[qinvokable]
        fn tenant_id(self: &Backend) -> QString;

        /// Save an app setting.
        #[qinvokable]
        fn set_setting(self: Pin<&mut Backend>, name: &QString, value: &QString);
        /// Tell the service you've done an engagement action (Teams'
        /// tracked actions), unless it knows already.
        #[qinvokable]
        fn record_engagement_action(self: Pin<&mut Backend>, action: &QString);

        /// Reply to a post in the open channel (`root_id` is the post's id).
        #[qinvokable]
        fn send_reply(self: Pin<&mut Backend>, root_id: &QString, text: &QString);

        /// Open a channel post's thread in a window of its own (Teams' Open
        /// conversation in new window): its messages load into
        /// thread_windows_json and stay live until it closes.
        #[qinvokable]
        fn open_thread_window(self: Pin<&mut Backend>, channel_id: &QString, root_id: &QString);
        #[qinvokable]
        fn close_thread_window(self: Pin<&mut Backend>, channel_id: &QString, root_id: &QString);
        /// A whole channel in a window of its own (Teams' channel Open in
        /// new window): its posts load into thread_windows_json under the
        /// channel's id and stay live until it closes.
        #[qinvokable]
        fn open_channel_window(self: Pin<&mut Backend>, channel_id: &QString);
        #[qinvokable]
        fn close_channel_window(self: Pin<&mut Backend>, channel_id: &QString);
        /// A chat in a window of its own (its menu's Open in new window):
        /// its messages load into thread_windows_json under "win:<chat>"
        /// and stay live until it closes.
        #[qinvokable]
        fn open_chat_window(self: Pin<&mut Backend>, chat_id: &QString);
        #[qinvokable]
        fn close_chat_window(self: Pin<&mut Backend>, chat_id: &QString);
        /// A message from a chat window (its compose's rich text, media and
        /// quote), to that chat.
        #[qinvokable]
        fn send_chat_window_message(self: Pin<&mut Backend>, chat_id: &QString, editor_html: &QString, media_json: &QString, quote_json: &QString);
        /// Files from a chat window, to that chat.
        #[qinvokable]
        fn send_chat_window_files(self: Pin<&mut Backend>, chat_id: &QString, paths: &QString, text: &QString);
        /// A new post from a channel window (its compose's rich text,
        /// media and quote).
        #[qinvokable]
        fn send_channel_post(
            self: Pin<&mut Backend>,
            channel_id: &QString,
            editor_html: &QString,
            media_json: &QString,
            quote_json: &QString,
        );
        /// Files sent as a reply in a thread window.
        #[qinvokable]
        fn send_thread_files(
            self: Pin<&mut Backend>,
            channel_id: &QString,
            root_id: &QString,
            paths: &QString,
            text: &QString,
        );
        /// Reply in a thread window: the compose's rich text, media and
        /// quote, sent to "<channel>;messageid=<post>".
        #[qinvokable]
        fn send_thread_reply(
            self: Pin<&mut Backend>,
            channel_id: &QString,
            root_id: &QString,
            editor_html: &QString,
            media_json: &QString,
            quote_json: &QString,
            also_channel: bool,
        );

        /// Start a group chat with these people (comma-separated object
        /// ids), optionally named, and send its first message.
        #[qinvokable]
        fn create_group_chat(
            self: Pin<&mut Backend>,
            oids: &QString,
            topic: &QString,
            first_message: &QString,
        );

        /// Store: load the app catalog into store_json.
        #[qinvokable]
        fn store_load(self: Pin<&mut Backend>);
        /// Load a Store page (a collection's See all, or a menu entry).
        #[qinvokable]
        fn store_page_load(self: Pin<&mut Backend>, id: &QString);
        /// Load an app's App permissions into app_permissions_json.
        #[qinvokable]
        fn app_permissions_load(self: Pin<&mut Backend>, app_id: &QString);
        /// Whether `kind` (media, geolocation, …) is allowed for an app,
        /// as App permissions has it.
        #[qinvokable]
        fn app_permission(self: Pin<&mut Backend>, app_id: &QString, kind: &QString) -> bool;
        /// Turn one of an app's device permissions on or off (kept on this
        /// device, as Teams keeps it).
        #[qinvokable]
        fn set_app_permission(self: Pin<&mut Backend>, app_id: &QString, kind: &QString, on: bool);
        /// Search the Store.
        #[qinvokable]
        fn store_search(self: Pin<&mut Backend>, query: &QString);

        /// A channel's tabs (Page, Notes, apps) into channel_tabs_json.
        #[qinvokable]
        fn channel_tabs_load(
            self: Pin<&mut Backend>,
            team_id: &QString,
            channel_id: &QString,
            channel_name: &QString,
        );

        /// Help › Collect Support Files, as Teams: OST's log in an
        /// "OST Support Logs <time>" folder on the Desktop, then the Desktop opened.
        #[qinvokable]
        fn collect_support_files(self: &Backend);
        /// The call or sharing state changed: publish presence as Teams does
        /// (Busy/InACall in a call, DoNotDisturb/Presenting while sharing,
        /// Available after).
        #[qinvokable]
        fn sync_call_presence(self: &Backend);
        /// Load the page of messages before the oldest shown.
        #[qinvokable]
        fn load_older_messages(self: Pin<&mut Backend>);
        /// About this tab: load the app's About (Teams' app definition).
        #[qinvokable]
        fn app_about_load(self: Pin<&mut Backend>, app_id: &QString);
        /// Load an app's details for Teams' About dialog.
        #[qinvokable]
        fn app_details_load(self: Pin<&mut Backend>, app_id: &QString);
        /// Load an app's reviews: `sort` "recent", "highest" or "lowest",
        /// `first` of them; `append` adds the next page to what's shown.
        #[qinvokable]
        fn app_reviews_load(self: Pin<&mut Backend>, app_id: &QString, sort: &QString, first: i32, append: bool);
        /// Hide a chat from the list until something newer is said, or show
        /// it again (Teams' Hide / Unhide).
        #[qinvokable]
        fn set_chat_hidden(self: Pin<&mut Backend>, chat_id: &QString, hidden: bool);
        /// Teams' Remove chat history: the chat leaves your list and its
        /// messages so far are gone for you only; an open one moves to the
        /// next chat.
        #[qinvokable]
        fn remove_chat_history(self: Pin<&mut Backend>, chat_id: &QString);
        /// Leave a group chat (Teams' Leave).
        #[qinvokable]
        fn leave_chat(self: Pin<&mut Backend>, chat_id: &QString);
        /// Count a group chat's members into chat_member_counts_json
        /// (Teams' Leave needs at least 3).
        #[qinvokable]
        fn chat_member_counts_load(self: Pin<&mut Backend>, chat_id: &QString);
        /// Load the chat list's sections.
        #[qinvokable]
        fn folders_load(self: Pin<&mut Backend>);
        /// Change the chat list's sections as Teams does: `action` is
        /// "expand"/"collapse" (folder id), "expandAll"/"collapseAll",
        /// "create" (name, optional item and from), "rename" (folder id,
        /// name), "delete" (folder id), "move" (item, to, optional from) or
        /// "remove" (item, from). `args` is a JSON object.
        #[qinvokable]
        fn folder_action(self: Pin<&mut Backend>, action: &QString, args: &QString);
        /// Look up an app's privacy and terms links (shared app cards).
        #[qinvokable]
        fn app_links_load(self: Pin<&mut Backend>, app_id: &QString);
        /// Load an app's "More like this".
        #[qinvokable]
        fn app_similar_load(self: Pin<&mut Backend>, app_id: &QString);
        /// Load Teams' "Add agent to the chat/channel" Store for a
        /// conversation (a channel when `channel`).
        #[qinvokable]
        fn agent_store_load(self: Pin<&mut Backend>, conversation_id: &QString, channel: bool);
        /// Search the agent Store for a conversation.
        #[qinvokable]
        fn agent_store_search(self: Pin<&mut Backend>, conversation_id: &QString, channel: bool, query: &QString);
        /// Add an app as Teams' Add does: for you, and to a conversation
        /// when `conversation_id` isn't empty.
        #[qinvokable]
        fn add_app(self: Pin<&mut Backend>, app_id: &QString, conversation_id: &QString, channel: bool);
        /// Share an app (Teams' Share form): `targets_json` as the Forward
        /// dialog's picks.
        #[qinvokable]
        fn share_app(self: Pin<&mut Backend>, app_id: &QString, targets_json: &QString, note: &QString, card: bool);
        /// The conversation the last share went to (the "shared" dialog's
        /// View opens it).
        #[qinvokable]
        fn shared_conversation(self: &Backend) -> QString;
        /// Report a review of an app (Teams' Report review).
        #[qinvokable]
        fn report_app_review(self: Pin<&mut Backend>, app_id: &QString, review_id: &QString, reason: &QString, comment: &QString);
        /// Post a review of an app (Teams' Write a review).
        #[qinvokable]
        fn post_app_review(self: Pin<&mut Backend>, app_id: &QString, rating: i32, title: &QString, content: &QString, anonymous: bool);
        /// Copy link to tab: Teams' deep link, as rich text with the tab's
        /// name (`tab_json` is the tab as channelTabsJson gives it).
        #[qinvokable]
        fn copy_tab_link(
            self: &Backend,
            team_id: &QString,
            channel_id: &QString,
            tab_json: &QString,
        );
        /// A channel tab's menu: "rename" (to `arg`), "left", "right" or
        /// "remove" tab `tab_id`, or "converse" (Start conversation in its
        /// Conversation pane; the outcome carries the new root post); the
        /// outcome goes to channelTabResult and the tabs reload.
        /// A channel's menu (More channel options, or its row in the list):
        /// "notify" (arg all|mentions|mute), "customize" (arg JSON {mode,
        /// tag, channel_team, dsk, follow_all, newest}), "notify-load",
        /// "hide", "show", "edit" (arg JSON {displayName?, description?,
        /// chatModalityType?}), "email" (get or create), "email-senders"
        /// (arg JSON {allowed, domains}), "email-remove", "copy-link" (arg
        /// the channel's name), "posts-at-top" / "posts-at-bottom". The
        /// outcome goes to channelActionResult; the team list reloads.
        #[qinvokable]
        fn channel_action(
            self: Pin<&mut Backend>,
            op: &QString,
            team_id: &QString,
            channel_id: &QString,
            arg: &QString,
        );
        #[qinvokable]
        fn channel_tab_change(
            self: Pin<&mut Backend>,
            op: &QString,
            team_id: &QString,
            channel_id: &QString,
            tab_id: &QString,
            arg: &QString,
        );

        /// A channel's Shared tab: list folder `item_id` of `drive_id`, or,
        /// with both empty, the channel's own folder (found from the team
        /// and channel), into channel_files_json.
        #[qinvokable]
        fn channel_files_load(
            self: Pin<&mut Backend>,
            team_id: &QString,
            channel_id: &QString,
            drive_id: &QString,
            item_id: &QString,
        );

        /// A channel's Shared tab: "upload" (paths, one per line), "folder"
        /// (a name), "delete" (an item id) or "shortcut" (add the folder to
        /// OneDrive, `arg` its name) in folder `item_id` of `drive_id`;
        /// then the folder reloads.
        #[qinvokable]
        fn channel_files_change(
            self: Pin<&mut Backend>,
            op: &QString,
            drive_id: &QString,
            item_id: &QString,
            arg: &QString,
        );

        /// OneNote: load "notebooks", "sections" (of notebook `id`),
        /// "pages" (of section `id`) or "page" (`id`'s content) into
        /// onenote_json.
        #[qinvokable]
        fn onenote_load(self: Pin<&mut Backend>, view: &QString, id: &QString);

        /// OneNote: create a notebook, a section in notebook `parent`, or a
        /// page (title, text) in section `parent`. kind: "notebook" |
        /// "section" | "page".
        #[qinvokable]
        fn onenote_create(
            self: Pin<&mut Backend>,
            kind: &QString,
            parent: &QString,
            name: &QString,
            text: &QString,
        );

        /// OneNote: delete a page.
        #[qinvokable]
        fn onenote_delete_page(self: Pin<&mut Backend>, id: &QString);

        /// People: load your contacts and categories into contacts_json.
        #[qinvokable]
        fn contacts_load(self: Pin<&mut Backend>);

        /// People: add a contact (NewContact as JSON).
        #[qinvokable]
        fn contacts_add(self: Pin<&mut Backend>, contact_json: &QString);

        /// People: mark a contact as a favorite, or not.
        #[qinvokable]
        fn contacts_favorite(self: Pin<&mut Backend>, id: &QString, on: bool);

        /// People: delete a contact.
        #[qinvokable]
        fn contacts_delete(self: Pin<&mut Backend>, id: &QString);

        /// Planner: load "mytasks", "plans" or "plan" (`plan_json` is a
        /// Plan) into planner_json.
        #[qinvokable]
        fn planner_load(self: Pin<&mut Backend>, view: &QString, plan_json: &QString);

        /// Planner: add a private task (due: YYYY-MM-DD or empty).
        #[qinvokable]
        fn planner_add(self: Pin<&mut Backend>, title: &QString, due: &QString);

        /// Planner: create a plan in a team.
        #[qinvokable]
        fn planner_create_plan(
            self: Pin<&mut Backend>,
            group_id: &QString,
            team: &QString,
            title: &QString,
        );

        /// Planner: add a task to the plan shown (Plan as JSON).
        #[qinvokable]
        fn planner_add_to_plan(self: Pin<&mut Backend>, plan_json: &QString, title: &QString);

        /// Planner: delete a plan (test clean-up and the plan menu).
        #[qinvokable]
        fn planner_delete_plan(self: Pin<&mut Backend>, plan_id: &QString);

        /// Planner: mark a task (Task as JSON) complete.
        #[qinvokable]
        fn planner_complete(self: Pin<&mut Backend>, task_json: &QString);

        /// Planner: delete a private task (Task as JSON).
        #[qinvokable]
        fn planner_delete(self: Pin<&mut Backend>, task_json: &QString);

        /// OneDrive: load a view into drive_json. `view` is "recent",
        /// "shared", "libraries" or "folder" (with `drive_id` and
        /// `item_id`; both empty for your OneDrive's root).
        #[qinvokable]
        fn drive_load(
            self: Pin<&mut Backend>,
            view: &QString,
            drive_id: &QString,
            item_id: &QString,
        );

        /// OneDrive: download a file (a DriveItem as JSON) to Downloads.
        #[qinvokable]
        fn drive_download(self: Pin<&mut Backend>, item_json: &QString);

        /// OneDrive: upload local files (newline-separated paths) to a folder.
        #[qinvokable]
        fn drive_upload(
            self: Pin<&mut Backend>,
            drive_id: &QString,
            folder_id: &QString,
            paths: &QString,
        );

        /// OneDrive: add an item to favorites, or take it off.
        #[qinvokable]
        fn drive_favorite(self: Pin<&mut Backend>, drive_id: &QString, item_id: &QString, on: bool);

        /// OneDrive: restore recycle-bin items (comma-separated ids).
        #[qinvokable]
        fn drive_restore(self: Pin<&mut Backend>, ids: &QString);

        /// OneDrive: delete recycle-bin items for good (comma-separated ids).
        #[qinvokable]
        fn drive_purge(self: Pin<&mut Backend>, ids: &QString);

        /// OneDrive: make a folder.
        #[qinvokable]
        fn drive_new_folder(
            self: Pin<&mut Backend>,
            drive_id: &QString,
            parent_id: &QString,
            name: &QString,
        );

        /// OneDrive: move an item to the recycle bin.
        #[qinvokable]
        fn drive_delete(self: Pin<&mut Backend>, drive_id: &QString, item_id: &QString);

        /// A Files item's More actions (docs/spec/file-actions.md) on a
        /// DriveItem (JSON): "rename" {name}; "move" / "copy" {dest} (a
        /// folder's web address); "duplicate"; "open_app" (a local copy,
        /// its path); "folders" {drive_id, item_id} (the Move to / Copy
        /// to picker's folder: {here, items}); "libraries" (the picker's
        /// Quick access). Ops may carry a "<tag>:" prefix. The answer comes back in
        /// drive_action_done.
        #[qinvokable]
        fn drive_action(self: Pin<&mut Backend>, op: &QString, item_json: &QString, args_json: &QString);

        /// Change an event's title and time (UTC).
        #[qinvokable]
        fn update_event(
            self: Pin<&mut Backend>,
            id: &QString,
            subject: &QString,
            start_utc: &QString,
            end_utc: &QString,
        );

        /// Delete an event (cancels a meeting you organise).
        #[qinvokable]
        fn delete_event(self: Pin<&mut Backend>, id: &QString);

        /// Create a calendar event (UTC times); optionally a Teams meeting.
        /// Attendees: comma- or semicolon-separated e-mail addresses.
        #[qinvokable]
        fn create_event(
            self: Pin<&mut Backend>,
            subject: &QString,
            start_utc: &QString,
            end_utc: &QString,
            attendees: &QString,
            teams_meeting: bool,
        );

        /// Mark every unread chat read (chat pane > More list options).
        #[qinvokable]
        fn mark_all_read(self: Pin<&mut Backend>);

        /// Load the team list again (after creating or joining a team).
        #[qinvokable]
        fn reload_teams(self: Pin<&mut Backend>);

        /// Set your status ("Available", "Busy", "DoNotDisturb",
        /// "BeRightBack", "Away", "Offline"), or "Reset".
        #[qinvokable]
        fn set_my_status(self: Pin<&mut Backend>, status: &QString);
        /// Set your status until a Duration choice (Teams' Duration page).
        #[qinvokable]
        fn set_my_status_until(
            self: Pin<&mut Backend>,
            status: &QString,
            duration: &QString,
            custom: &QString,
        );
        /// Set or clear your status message (Teams' Set status message).
        #[qinvokable]
        fn set_status_note(
            self: Pin<&mut Backend>,
            message: &QString,
            pinned: bool,
            clear_after: &QString,
            custom: &QString,
        );

        /// Microphones and speakers: {"inputs": [...], "outputs": [...]}.
        #[qinvokable]
        fn audio_devices(self: Pin<&mut Backend>) -> QString;
        /// The call's speaker volume, 0-100 (Teams' in-call slider).
        #[qinvokable]
        fn speaker_volume(self: Pin<&mut Backend>) -> i32;
        #[qinvokable]
        fn set_speaker_volume(self: Pin<&mut Backend>, volume: i32);
        /// The microphone's current level, 0-100 (Teams' in-call meter).
        #[qinvokable]
        fn mic_level(self: Pin<&mut Backend>) -> i32;

        /// Ask for someone's profile card to open (a picture was clicked).
        #[qinvokable]
        fn request_profile(self: Pin<&mut Backend>, mri: &QString);
        #[qsignal]
        fn profile_requested(self: Pin<&mut Backend>, mri: QString);
        /// Load someone's profile card (an MRI "8:orgid:…" or object id)
        /// into profile_card_json.
        #[qinvokable]
        fn load_profile_card(self: Pin<&mut Backend>, who: &QString);
        /// Settings ▸ Notifications ▸ Test notification: Teams' sample.
        #[qinvokable]
        fn test_notification(self: Pin<&mut Backend>);
        /// A notification went out: flash the taskbar (if that's on).
        #[qsignal]
        fn flash_requested(self: Pin<&mut Backend>);
        /// Where downloads are saved now (Settings ▸ Files and links).
        #[qinvokable]
        fn download_location(self: Pin<&mut Backend>) -> QString;
        /// The desktop's app for Word files (its name), empty when there
        /// is none: Settings ▸ Files and links offers "Desktop app" then.
        #[qinvokable]
        fn office_app_name(self: Pin<&mut Backend>) -> QString;
        /// Open a file as Teams' "Always open Word, PowerPoint, and Excel
        /// files in" says: Word, PowerPoint and Excel files in the
        /// desktop app (a downloaded copy) when that is chosen on this
        /// device (setting "fileOpenIn" = "desktop"), else everything in
        /// the browser. `item_json` is its DriveItem when known (else the
        /// file is found by its address).
        #[qinvokable]
        fn open_file(self: Pin<&mut Backend>, url: &QString, name: &QString, item_json: &QString);
        /// Load Settings' synced values (into settings_json): {props: your
        /// user properties, JSON ones parsed; mt: the middle tier's
        /// settings}.
        #[qinvokable]
        fn load_settings(self: Pin<&mut Backend>);
        /// Change a synced setting: kind "prop" (a user property; value is
        /// a JSON patch for object properties or a JSON string) or "mt" (a
        /// middle-tier setting; value "true"/"false"). The outcome goes to
        /// settings_json (and settings_error on failure).
        #[qinvokable]
        fn change_setting(self: Pin<&mut Backend>, kind: &QString, name: &QString, value_json: &QString);
        /// Load the read receipts setting from Teams (into read_receipts).
        #[qinvokable]
        fn load_read_receipts(self: Pin<&mut Backend>);

        /// Turn read receipts on or off in Teams.
        #[qinvokable]
        fn change_read_receipts(self: Pin<&mut Backend>, on: bool);

        /// Send files (newline-separated paths or file:// URLs) to the open
        /// chat, with optional text, the way Teams does.
        #[qinvokable]
        fn send_files(self: Pin<&mut Backend>, paths: &QString, text: &QString);

        /// Save an attachment into the Downloads folder.
        #[qinvokable]
        fn download_file(self: Pin<&mut Backend>, file_json: &QString);

        /// Send a formatted message (the compose editor's rich text).
        #[qinvokable]
        fn send_rich(self: Pin<&mut Backend>, editor_html: &QString);

        /// As send_rich, with the fun picker's emoticons, GIFs and stickers
        /// in the compose box (`media_json`: [{src, kind, id, title,
        /// unicode, url, width, height}]) sent in Teams' form.
        #[qinvokable]
        fn send_rich_media(self: Pin<&mut Backend>, editor_html: &QString, media_json: &QString);
    }

    impl cxx_qt::Threading for Backend {}
}

#[derive(Default)]
pub struct BackendRust {
    busy: bool,
    signed_in: bool,
    user_name: QString,
    user_mail: QString,
    org_name: QString,
    status_text: QString,
    chats_json: QString,
    messages_json: QString,
    current_chat_id: QString,
    current_chat_name: QString,
    has_credentials: bool,
    sign_in_code: QString,
    sign_in_url: QString,
    call_state: QString,
    call_peer: QString,
    call_peer_id: QString,
    call_video_offered: bool,
    call_meeting: bool,
    drive_json: QString,
    drive_busy: bool,
    store_json: QString,
    channel_tabs_json: QString,
    channel_tab_result: QString,
    app_about_json: QString,
    app_details_json: QString,
    app_reviews_json: QString,
    app_similar_json: QString,
    agent_store_json: QString,
    store_page_json: QString,
    app_permissions_json: QString,
    store_search_json: QString,
    agent_search_json: QString,
    app_added_json: QString,
    app_links_json: QString,
    folders_json: QString,
    chat_member_counts_json: QString,
    team_tags_json: QString,
    folders: teams_cli::api::folders::Folders,
    /// Apps whose links were asked for already.
    app_links_asked: std::collections::HashSet<String>,
    share_state: QString,
    /// Where the last share went (the "View" button opens it).
    shared_to: String,
    status_note_result: QString,
    my_note_json: QString,
    my_status_ends: QString,
    settings_json: QString,
    profile_card_json: QString,
    scheduled_json: QString,
    find_json: QString,
    search_page_json: QString,
    search_in_json: QString,
    search_page_key: String,
    find_people_json: QString,
    /// The search Find in chat shows (newer searches drop older replies).
    find_key: String,
    /// The next message from the compose goes at this time (Schedule
    /// message), epoch ms.
    next_schedule_ms: Option<i64>,
    settings_error: QString,
    my_work_location: QString,
    thread_windows_json: QString,
    channel_action_result: QString,
    channel_posts_at_top: bool,
    /// The threads open in windows ("<channel>;messageid=<post>").
    thread_windows: Vec<String>,
    messages_has_older: bool,
    messages_loading_older: bool,
    /// The channel name channel_tabs_load was last given (reloads reuse it).
    channel_tabs_name: String,
    store_busy: bool,
    channel_files_json: QString,
    channel_files_busy: bool,
    onenote_json: QString,
    onenote_busy: bool,
    contacts_json: QString,
    contacts_busy: bool,
    planner_json: QString,
    planner_busy: bool,
    /// The Planner view last asked for (view, plan json), to reload.
    planner_view: (String, String),
    /// The OneDrive view last asked for, to reload after a change.
    drive_view: (String, String, String),
    call_can_video: bool,
    call_camera_on: bool,
    call_roster_json: QString,
    call_video_json: QString,
    call_speaker_mri: QString,
    call_speaking_json: QString,
    call_muted_by_meeting: bool,
    chat_live_roster_json: QString,
    call_muted_remotely: i32,
    call_meeting_locked: bool,
    call_network_strength: QString,
    call_scheduled: bool,
    call_lobby_presenter: bool,
    call_attendee_restrictions: i32,
    call_speaking_while_muted: bool,
    call_ai_indicator: bool,
    call_ai_available: bool,
    call_ai_facilitator: bool,
    call_everyone_presents: bool,
    call_ai_on: bool,
    call_recording_state: QString,
    call_recording_tip: QString,
    call_meeting_info_json: QString,
    call_end_reason: QString,
    call_controls_json: QString,
    people_names_json: QString,
    call_transcript_json: QString,
    call_captions_json: QString,
    call_captions_on: bool,
    call_timer_json: QString,
    call_health_json: QString,
    /// The meeting timer's clock skew (now − the service's stamp, from
    /// live updates only), ms.
    timer_skew_ms: i64,
    call_rtt_on: bool,
    call_rtt_initiator: bool,
    call_privacy_url: QString,
    /// Real-time text lines being typed, by sender's data source.
    rtt_lines: teams_cli::calling::rtt::Lines,
    /// The RTT lines typed now, one per person (the captions window lists
    /// them after the captions).
    rtt_typing: Vec<teams_cli::calling::transcript::Entry>,
    /// The RTT box: what it says, and what's still to send.
    rtt_box: teams_cli::calling::rtt::Input,
    call_captions_language: QString,
    call_accessibility_json: QString,
    call_notifications_muted: bool,
    call_chat_bubbles_suppressed: bool,
    /// Live captions' recent results.
    captions: Vec<teams_cli::calling::transcript::Entry>,
    /// Captions started for us and our endpoint says we want them.
    captions_published: bool,
    /// The Transcript pane's rows.
    transcript: Vec<teams_cli::calling::transcript::Entry>,
    /// What Copy join info copies (HTML, text).
    meeting_join_info: (String, String),
    /// The meeting last joined (link, title), for Rejoin.
    last_join: (QString, QString),
    /// What the meeting's call recorder does (for the recording
    /// indicator's names as the roster changes).
    processing: teams_cli::calling::roster::Processing,
    call_lock_notices: i32,
    /// Who joined and left the meeting we're in (the attendance list).
    attendance: teams_cli::calling::meeting_options::AttendanceLog,
    call_share_mri: QString,
    /// How wide each person's tile is drawn ({mri: px}), for the size of
    /// video to ask for.
    video_widths: std::collections::HashMap<String, f64>,
    call_lobby_json: QString,
    call_thread_id: QString,
    user_mri: QString,
    roster: Vec<teams_cli::calling::roster::Participant>,
    /// Your own roster entry (role, state) in a main meeting put on hold
    /// for a breakout room: the room's roster replaces it meanwhile.
    held_self: Vec<teams_cli::calling::roster::Participant>,
    /// Others' videos are turned off (View › More options).
    incoming_video_off: bool,
    call_muted: bool,
    /// We asked the meeting to lift its mute; the mic opens once the
    /// roster says it did (as Teams does).
    unmute_pending: bool,
    call_held: bool,
    call_held_by_peer: bool,
    call_can_dtmf: bool,
    call_can_share: bool,
    call_sharing: bool,
    call_hand_raised: bool,
    call_options_url: QString,
    call_chat_url: QString,
    call_invite_url: QString,
    call_has_audio: bool,
    typing_text: QString,
    emoticons_version: i32,
    recent_reactions_json: QString,
    skin_tone: i32,
    header_call_video: bool,
    reaction_prefs_result: QString,
    message_readers_json: QString,
    toast_json: QString,
    pinned_json: QString,
    report_result: QString,
    quick_reactions_json: QString,
    typing_avatar: QString,
    typing_avatar_id: QString,
    window_active: bool,
    system_frame: bool,
    drafts_json: QString,
    activity_json: QString,
    activity_unread: i32,
    theme_mode: QString,
    read_receipts: bool,
    calls_json: QString,
    calendar_json: QString,
    people_json: QString,
    chat_members_json: QString,
    call_chat_members_json: QString,
    chat_meeting_json: QString,
    attendance_json: QString,
    call_lobby_thread: QString,
    call_breakout_json: QString,
    call_breakout_rooms_json: QString,
    call_breakout_all_json: QString,
    call_breakout_room_json: QString,
    call_held_meeting_json: QString,
    esp_actions_json: QString,
    fun_results_json: QString,
    custom_emoji_json: QString,
    custom_emoji_result: QString,
    custom_emoji_can_add: bool,
    custom_emoji_can_delete: bool,
    teams_json: QString,
    people_query_generation: u64,
    /// Bumped on every typing change so a stale clear timer does nothing.
    typing_generation: u64,
    /// Who is typing in the open chat (key: MRI, else name), shown as
    /// whom, and until when (Teams keeps a typer 22 s after their last
    /// typing event).
    typers: Vec<Typer>,
    /// The message the next send quotes.
    reply_quote: Option<api::messages::Quote>,
    next_importance: String,
    /// The next channel post's subject, headline and banner colour.
    next_post: Option<NextPost>,
    last_typing_sent: Option<std::time::Instant>,
    /// Chats with messages pushed since the user last opened them.
    unread: HashSet<String>,
    /// The chat list as loaded, before unread flags are applied.
    chats: Vec<serde_json::Value>,
    /// The newest message id in the open chat.
    newest_message_id: Option<(String, String)>,
    /// The last message id we marked read, per chat.
    marked_read: std::collections::HashMap<String, String>,
    /// Our own MRI, to tell our messages apart in pushes.
    my_mri: Option<String>,
    /// Availability by MRI for the other members of 1:1 chats.
    presence: std::collections::HashMap<String, String>,
    /// Others' status messages and out of office, by MRI: {text, html,
    /// pinned, ooo} (Teams' banner over the compose box of a 1:1).
    peer_notes: std::collections::HashMap<String, serde_json::Value>,
    /// Channels' layouts from the chat service (the teams list leaves some
    /// out), by channel id.
    channel_layouts: std::collections::HashMap<String, String>,
    /// Pictures by photo_for id: a file URL, or None for "has none".
    photos: HashMap<String, Option<String>>,
    /// Picture downloads in flight.
    photo_fetching: HashSet<String>,
    /// Files' preview pictures by link (file URL, or None for "has none"),
    /// and those downloading.
    thumbnails: HashMap<String, Option<String>>,
    thumbnail_fetching: HashSet<String>,
    /// The calendar range last shown (UTC start, end), for refreshing.
    calendar_range: Option<(String, String)>,
    /// Unsent drafts by chat id: (text, unix ms when last edited).
    drafts: Option<HashMap<String, (String, u64)>>,
}

/// The call this app is ringing for or in. Lives on the engine side so the
/// media keeps running independently of the Qt thread.
#[derive(Default)]
struct CallSlot {
    ringing: Option<IncomingCall>,
    active: Option<ActiveCall>,
    outgoing: Option<OutgoingCall>,
    /// The meeting we're moving out of (to a breakout room or back): its
    /// media is off, and it is left once the next meeting answers.
    moved_from: Option<OutgoingCall>,
    /// The ids of the meetings we moved out of: their ends are theirs.
    left_calls: Vec<String>,
    /// The main meeting on hold while its organizer is in a breakout room
    /// (Teams' Join on a room's menu), with its link and title.
    held_main: Option<(OutgoingCall, QString, QString)>,
    /// The callback tags of the calls we moved out of: their events
    /// (their conversation ending as we leave) are theirs.
    left_tags: Vec<String>,
    /// Withdraws the call being placed (still ringing the callee).
    cancel_placing: Option<tokio::sync::oneshot::Sender<()>>,
    /// The screen picked to share, waiting for Teams to take our re-offer.
    share_pending: Option<(
        teams_cli::calling::screencast::ScreenCapture,
        std::sync::mpsc::Receiver<teams_cli::calling::camera::YuvFrame>,
    )>,
}

/// The connected call, answered or placed: what changing our media
/// (camera, screen) needs from it.
enum MediaCall<'a> {
    Answered(&'a mut ActiveCall),
    Placed(&'a mut OutgoingCall),
}

macro_rules! either {
    ($self:expr, $c:ident => $e:expr) => {
        match $self {
            MediaCall::Answered($c) => $e,
            MediaCall::Placed($c) => $e,
        }
    };
}

impl MediaCall<'_> {
    fn of(slot: &mut CallSlot) -> Option<MediaCall<'_>> {
        match (slot.active.as_mut(), slot.outgoing.as_mut()) {
            (Some(c), _) => Some(MediaCall::Answered(c)),
            (None, Some(c)) => Some(MediaCall::Placed(c)),
            _ => None,
        }
    }

    async fn offer_media(&mut self, change: Reoffer) -> anyhow::Result<()> {
        match self {
            MediaCall::Answered(c) => c.offer_media(&CallAuth::load().await?, change).await,
            MediaCall::Placed(c) => c.offer_media(change).await,
        }
    }

    async fn acknowledge_answer(&self, link: &str) -> anyhow::Result<()> {
        match self {
            MediaCall::Answered(c) => c.acknowledge_answer(&CallAuth::load().await?, link).await,
            MediaCall::Placed(c) => c.acknowledge_answer(link).await,
        }
    }

    fn can_reoffer(&self) -> bool {
        either!(self, c => c.can_reoffer())
    }

    /// A meeting's (or group call's) camera and screen go on and off by
    /// media descriptions, as Teams does, not re-offers.
    fn describes_media(&self) -> bool {
        matches!(self, MediaCall::Placed(c) if c.describes_media())
    }

    fn can_share(&self) -> bool {
        either!(self, c => c.can_share())
    }

    fn reoffer_pending(&self) -> bool {
        either!(self, c => c.reoffer_pending())
    }

    fn take_reoffer_answer(&mut self, answer: &str) -> anyhow::Result<(Reoffer, bool)> {
        either!(self, c => c.take_reoffer_answer(answer))
    }

    fn cancel_reoffer(&self) {
        either!(self, c => c.cancel_reoffer())
    }

    fn set_camera(&mut self, on: bool) -> anyhow::Result<()> {
        either!(self, c => c.set_camera(on, camera_device()))
    }

    fn start_share(
        &mut self,
        capture: teams_cli::calling::screencast::ScreenCapture,
        frames: std::sync::mpsc::Receiver<teams_cli::calling::camera::YuvFrame>,
    ) -> anyhow::Result<()> {
        either!(self, c => c.start_share(capture, frames))
    }

    fn stop_share(&mut self) {
        either!(self, c => c.stop_share())
    }

    fn is_sharing(&self) -> bool {
        either!(self, c => c.is_sharing())
    }

    fn share_ended(&self) -> bool {
        either!(self, c => c.share_ended())
    }
}

/// Tell a meeting what our camera and sharing lines now do, as Teams
/// does when either changes.
async fn describe_media(call: Option<&OutgoingCall>) -> anyhow::Result<()> {
    match call {
        Some(o) => o.describe_media(o.camera_on(), o.is_sharing()).await,
        None => Ok(()),
    }
}

/// Ask the desktop what to share (its picker), then offer it to the call.
/// Sending starts when Teams answers ([`reoffer_reply`]); in a meeting it
/// starts at once and the meeting is told (returns true).
async fn offer_screen() -> anyhow::Result<bool> {
    // Only open the desktop's picker when the call can take a screen.
    {
        let mut slot = call_slot().lock().await;
        let call = MediaCall::of(&mut slot).context("The call has ended")?;
        anyhow::ensure!(call.can_share(), "This call can't take a shared screen");
    }
    let (capture, frames) = teams_cli::calling::screencast::ScreenCapture::start().await?;
    let mut guard = call_slot().lock().await;
    let slot = &mut *guard;
    let mut call = MediaCall::of(slot).context("The call has ended")?;
    if call.describes_media() {
        call.start_share(capture, frames)?;
        if let Err(e) = describe_media(slot.outgoing.as_ref()).await {
            if let Some(mut call) = MediaCall::of(slot) {
                call.stop_share();
            }
            return Err(e);
        }
        return Ok(true);
    }
    call.offer_media(Reoffer::Share(true)).await?;
    slot.share_pending = Some((capture, frames));
    Ok(false)
}

/// Stop sending our screen and tell the call.
async fn stop_screen() -> anyhow::Result<()> {
    let mut guard = call_slot().lock().await;
    let slot = &mut *guard;
    slot.share_pending = None;
    let mut call = MediaCall::of(slot).context("The call has ended")?;
    call.stop_share();
    if call.describes_media() {
        return describe_media(slot.outgoing.as_ref()).await;
    }
    call.offer_media(Reoffer::Share(false)).await
}

/// Teams' reply to a re-offer of ours (camera or screen). Returns false
/// when it isn't one (some other mediaAnswer), so the event is handled as
/// before.
async fn reoffer_reply(
    qt: &cxx_qt::CxxQtThread<qobject::Backend>,
    reply: anyhow::Result<teams_cli::calling::incoming::ReofferAnswer>,
) -> bool {
    let mut guard = call_slot().lock().await;
    let slot = &mut *guard;
    let pending = slot.share_pending.take();
    let Some(mut call) = MediaCall::of(slot).filter(|c| c.reoffer_pending()) else {
        slot.share_pending = pending;
        return false;
    };
    let outcome = match reply {
        Ok(answer) => {
            if let Some(link) = &answer.ack
                && let Err(e) = call.acknowledge_answer(link).await
            {
                tracing::warn!("re-offer: {}", short_error(&e));
            }
            call.take_reoffer_answer(&answer.sdp)
        }
        Err(e) => {
            call.cancel_reoffer();
            Err(e)
        }
    };
    // What the UI shows afterwards: (camera, sharing), when they change.
    let result: anyhow::Result<(Option<bool>, Option<bool>)> = match (outcome, pending) {
        (Ok((Reoffer::Share(true), true)), Some((capture, frames))) => call
            .start_share(capture, frames)
            .map(|()| (None, Some(true))),
        (Ok((Reoffer::Share(true), _)), _) => {
            Err(anyhow::anyhow!("The call didn't take your screen"))
        }
        (Ok((Reoffer::Share(false), _)), _) => Ok((None, Some(false))),
        (Ok((Reoffer::Camera(true), true)), _) => {
            call.set_camera(true).map(|()| (Some(true), None))
        }
        (Ok((Reoffer::Camera(true), false)), _) => {
            Err(anyhow::anyhow!("The call didn't take your camera"))
        }
        (Ok((Reoffer::Camera(false), _)), _) => Ok((Some(false), None)),
        (Err(e), _) => Err(e),
    };
    // A meeting is told what our camera and sharing lines now do, as Teams
    // does, so its roster shows them and others can ask for them.
    drop(guard);
    match result {
        Ok((camera, sharing)) => {
            tracing::info!(?camera, ?sharing, "media changed");
            let _ = qt.queue(move |mut this| {
                if let Some(c) = camera {
                    this.as_mut().set_call_camera_on(c);
                }
                if let Some(s) = sharing {
                    this.as_mut().set_call_sharing(s);
                }
            });
            if sharing == Some(true) {
                spawn_share_watch(qt.clone());
            }
        }
        Err(e) => {
            tracing::warn!("re-offer: {}", short_error(&e));
            let _ = qt.queue(move |mut this| {
                this.as_mut().set_call_sharing(false);
                this.as_mut()
                    .set_status_text(QString::from(short_error(&e).as_str()));
            });
        }
    }
    true
}

/// While we share: when the shared window goes away (or sharing is
/// stopped from the desktop), stop and tell the call, as Teams does.
fn spawn_share_watch(qt: cxx_qt::CxxQtThread<qobject::Backend>) {
    runtime().spawn(async move {
        loop {
            tokio::time::sleep(std::time::Duration::from_secs(1)).await;
            let mut slot = call_slot().lock().await;
            let Some(call) = MediaCall::of(&mut slot) else {
                return;
            };
            if !call.is_sharing() {
                return;
            }
            if call.share_ended() {
                drop(slot);
                if let Err(e) = stop_screen().await {
                    tracing::warn!("share: {}", short_error(&e));
                }
                let _ = qt.queue(|mut this| this.as_mut().set_call_sharing(false));
                return;
            }
        }
    });
}

/// The chat call we're watching without joining (its live roster).
fn watched_call() -> &'static tokio::sync::Mutex<Option<teams_cli::calling::live_roster::LiveRoster>>
{
    static W: OnceLock<tokio::sync::Mutex<Option<teams_cli::calling::live_roster::LiveRoster>>> =
        OnceLock::new();
    W.get_or_init(Default::default)
}

/// The watched call's roster for the header: [{id, name}] of who's in it.
fn live_roster_json(w: &teams_cli::calling::live_roster::LiveRoster) -> String {
    let people: Vec<serde_json::Value> = w
        .others()
        .map(|p| serde_json::json!({"id": p.id, "name": p.name}))
        .collect();
    serde_json::to_string(&people).unwrap_or_else(|_| "[]".into())
}

/// Run a breakout rooms action on the meeting `link` names and read the
/// rooms and settings back (the state call_breakout_rooms_json shows).
async fn breakout_run(action: &str, args: &serde_json::Value, link: &outgoing::MeetingLink) -> anyhow::Result<serde_json::Value> {
    use api::breakout_rooms as br;
    let client = TeamsClient::new().await?;
    let main = br::Coords::new(
        link.tenant_id.as_deref().unwrap_or_default(),
        link.organizer_id.as_deref().unwrap_or_default(),
        &link.thread_id,
        &link.message_id,
    )?;
    let me = call_slot().lock().await.outgoing.as_ref().map(|c| c.participant_id().to_string()).unwrap_or_default();
    let version = br::new_version(&me);
    let total = args["total"].as_u64().unwrap_or(0) as usize;
    let str_of = |v: &serde_json::Value| v.as_str().unwrap_or_default().to_string();
    let rooms_now = || async { br::list(&client, &main).await };
    let pick = |rooms: &[br::Room], threads: &serde_json::Value| -> Vec<br::Coords> {
        let wanted: Vec<String> = threads.as_array().map(|a| a.iter().map(str_of).collect()).unwrap_or_default();
        rooms.iter().filter(|r| wanted.is_empty() || wanted.contains(&r.coords.thread)).map(|r| r.coords.clone()).collect()
    };
    let find = |rooms: &[br::Room], thread: &str| rooms.iter().find(|r| r.coords.thread == thread).cloned();
    let mut csv_warnings: Vec<String> = Vec::new();
    match action {
        "refresh" => {}
        "create" => {
            let rooms: Vec<br::NewRoom> = args["rooms"]
                .as_array()
                .into_iter()
                .flatten()
                .map(|r| br::NewRoom {
                    name: str_of(&r["name"]),
                    participants: r["participants"].as_array().cloned().unwrap_or_default(),
                })
                .collect();
            if rooms.is_empty() {
                anyhow::bail!("No rooms to create");
            }
            let settings = args.get("settings").map(br::Settings::from_args);
            br::create(&client, &main, &rooms, settings.as_ref(), &version).await?;
        }
        "assign" => {
            let current = rooms_now().await?;
            let mut rooms = Vec::new();
            for r in args["rooms"].as_array().into_iter().flatten() {
                let mut room = find(&current, &str_of(&r["thread"])).context("No such room")?;
                if let Some(n) = r["name"].as_str() {
                    room.name = n.to_string();
                }
                room.participants = r["participants"].as_array().cloned().unwrap_or_default();
                rooms.push(room);
            }
            br::assign(&client, &main, &rooms, total, &version).await?;
        }
        "open" | "close" => {
            let current = rooms_now().await?;
            let rooms = pick(&current, &args["threads"]);
            if rooms.is_empty() {
                anyhow::bail!("No rooms");
            }
            if action == "open" {
                br::open(&client, &main, &rooms, total, &version).await?;
            } else {
                br::close(&client, &main, &rooms, total, &version).await?;
            }
        }
        "settings" => {
            br::set_settings(&client, &main, &br::Settings::from_args(args), &version).await?;
        }
        "add" => br::add_room(&client, &main, &str_of(&args["name"]), &[], &version).await?,
        "rename" => {
            let mut room = find(&rooms_now().await?, &str_of(&args["thread"])).context("No such room")?;
            room.name = str_of(&args["name"]);
            br::update_room(&client, &room, &version).await?;
        }
        "delete" => {
            let room = find(&rooms_now().await?, &str_of(&args["thread"])).context("No such room")?;
            br::delete_room(&client, &room.coords, &version).await?;
        }
        "delete_all" => br::delete_all(&client, &main, &rooms_now().await?, &version).await?,
        // Teams' Download CSV template: saved to Downloads.
        "csv_template" => {
            let dir = download_dir().context("No Downloads folder")?;
            let path = api::files::save_unique(&dir, br::CSV_TEMPLATE_NAME, br::CSV_TEMPLATE.as_bytes())?;
            tracing::info!(path = %path.display(), "breakout CSV template saved");
        }
        // Teams' Import from CSV: the rooms and their people from the file,
        // matched by email to the meeting's invitees; rooms already made
        // are replaced.
        "import_csv" => {
            let path = std::path::PathBuf::from(str_of(&args["path"]));
            if path.extension().and_then(|e| e.to_str()).map(|e| e.to_ascii_lowercase()) != Some("csv".into()) {
                anyhow::bail!("We couldn't import this file. The file type, size, or content isn't supported. Please update the file and try again.");
            }
            let text = std::fs::read_to_string(&path).context("We couldn't import this file. The file type, size, or content isn't supported. Please update the file and try again.")?;
            let import = br::parse_csv(&text)?;
            let invitees = api::meeting_options::get(&client, &main.tenant, &main.organizer, &main.thread, &main.message).await?.invitees;
            let mut warnings: Vec<&str> = import.warnings.clone();
            let mut rooms = Vec::new();
            for (name, emails) in &import.rooms {
                let mut people = Vec::new();
                for email in emails {
                    let found = invitees.iter().find(|i| {
                        i["upn"].as_str().or(i["email"].as_str()).is_some_and(|u| u.eq_ignore_ascii_case(email))
                    });
                    match found {
                        Some(i) if i["mri"].is_string() && i["objectId"].is_string() => people.push(json!({
                            "upn": email, "mri": i["mri"], "objectId": i["objectId"], "role": "admin",
                            "tenantId": i.get("tenantId").cloned().unwrap_or(json!(main.tenant)),
                        })),
                        _ => {
                            if !warnings.contains(&"UNMATCHED_PARTICIPANTS") {
                                warnings.push("UNMATCHED_PARTICIPANTS");
                            }
                        }
                    }
                }
                rooms.push(br::NewRoom { name: name.clone(), participants: people });
            }
            let existing = rooms_now().await?;
            if !existing.is_empty() {
                br::delete_all(&client, &main, &existing, &br::new_version(&me)).await?;
            }
            br::create(&client, &main, &rooms, None, &version).await?;
            tracing::info!(rooms = rooms.len(), ?warnings, "breakout rooms imported");
            csv_warnings = warnings.iter().map(|w| w.to_string()).collect();
        }
        "announce" => {
            let threads: Vec<String> = rooms_now().await?.into_iter().map(|r| r.coords.thread).collect();
            br::announce(&client, &main, &threads, &str_of(&args["message"])).await?;
        }
        other => anyhow::bail!("Unknown breakout action {other}"),
    }
    let rooms = rooms_now().await?;
    let settings = br::settings(&client, &main).await.unwrap_or_default();
    Ok(json!({
        "rooms": rooms.iter().map(|r| json!({
            "name": r.name,
            "thread": r.coords.thread,
            "join_url": r.join_url,
            "open": r.open,
            "participants": r.participants,
        })).collect::<Vec<_>>(),
        "settings": settings,
        "loaded": true,
        "warnings": csv_warnings,
    }))
}

/// What the call window shows of a meeting once it's joined (or resumed).
struct JoinedView {
    invite: String,
    capability: teams_cli::calling::meeting_options::MeetingCapability,
    processing: teams_cli::calling::roster::Processing,
    ai_indicator: bool,
    has_audio: bool,
    can_dtmf: bool,
    // Camera and Share as the joined media allows (in the lobby Share
    // waits for the admission's links).
    can_video: bool,
    can_share: bool,
    started: bool,
    timers: teams_cli::calling::meeting_timer::Timers,
}

impl JoinedView {
    fn of(call: &OutgoingCall) -> Self {
        Self {
            invite: call.invite_url().unwrap_or_default().to_string(),
            capability: call.capability(),
            processing: call.processing(),
            ai_indicator: call.shows_ai_indicator(),
            has_audio: call.has_audio(),
            can_dtmf: call.can_dtmf(),
            can_video: call.can_send_video(),
            can_share: call.can_share(),
            started: call.meeting_started(),
            timers: call.timers().clone(),
        }
    }
}

/// Leave the meeting we moved out of (its media is already off).
async fn leave_moved_from(call: OutgoingCall) {
    match call.hang_up().await {
        Ok(()) => tracing::info!("left the meeting we moved out of"),
        Err(e) => tracing::warn!("leaving the meeting we moved out of: {}", short_error(&e)),
    }
}

fn call_slot() -> &'static tokio::sync::Mutex<CallSlot> {
    static SLOT: OnceLock<tokio::sync::Mutex<CallSlot>> = OnceLock::new();
    SLOT.get_or_init(Default::default)
}

/// Where our own RTT lines are kept apart from everyone else's (Teams
/// uses its own data source; ours is known only once the channel is up).
const OWN_RTT_SOURCE: u32 = u32::MAX;

/// Our RTT chunks, sent in the order typed by one task.
fn rtt_outbox() -> &'static tokio::sync::mpsc::UnboundedSender<String> {
    static OUTBOX: OnceLock<tokio::sync::mpsc::UnboundedSender<String>> = OnceLock::new();
    OUTBOX.get_or_init(|| {
        let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel::<String>();
        runtime().spawn(async move {
            while let Some(chunk) = rx.recv().await {
                let sent = call_slot()
                    .lock()
                    .await
                    .outgoing
                    .as_ref()
                    .is_some_and(|call| call.send_real_time_text(&chunk));
                if !sent {
                    tracing::warn!("real-time text: the call has no meeting data channel");
                }
            }
        });
        tx
    })
}

/// Log media health every 5 s while a call lasts.
fn spawn_call_stats_logger(qt: cxx_qt::CxxQtThread<qobject::Backend>) {
    runtime().spawn(async move {
        let mut tick = 0u64;
        let mut muted_speech = teams_cli::calling::muted_speech::Detector::new();
        // Call health's 15 s window starts with the call.
        *health_sampler().lock().unwrap_or_else(|e| e.into_inner()) =
            teams_cli::calling::call_health::Sampler::new();
        let mut speaking_muted = false;
        loop {
            tokio::time::sleep(std::time::Duration::from_secs(1)).await;
            tick += 1;
            health_sampler().lock().unwrap_or_else(|e| e.into_inner()).sample(
                &teams_cli::calling::call_health::current(),
                chrono::Utc::now().timestamp_millis(),
            );
            // Talking with the mic off (Teams checks with each stats poll).
            let muted = {
                let slot = call_slot().lock().await;
                match (slot.active.as_ref(), slot.outgoing.as_ref()) {
                    (Some(call), _) => Some(call.is_muted()),
                    (None, Some(call)) => Some(call.is_muted() || call.is_server_muted()),
                    (None, None) => None,
                }
            };
            if let Some(muted) = muted {
                let now = muted_speech.report(muted, teams_cli::calling::audio::mic_recent_level());
                if now != speaking_muted {
                    speaking_muted = now;
                    tracing::info!(speaking_muted = now, "speaking while muted");
                    let _ = qt.queue(move |mut this| this.as_mut().set_call_speaking_while_muted(now));
                }
            }
            // Teams' network strength (your name tag's bars), each second.
            let strength = {
                let slot = call_slot().lock().await;
                if let Some(call) = slot.active.as_ref() {
                    Some(call.network_strength())
                } else {
                    slot.outgoing.as_ref().map(|c| c.network_strength())
                }
            };
            let Some(strength) = strength else {
                if speaking_muted {
                    let _ = qt.queue(|mut this| this.as_mut().set_call_speaking_while_muted(false));
                }
                return;
            };
            let name = strength.name();
            let _ = qt.queue(move |mut this| {
                if this.rust().call_network_strength.to_string() != name {
                    this.as_mut().set_call_network_strength(QString::from(name));
                }
            });
            if tick % 5 != 0 {
                continue;
            }
            let slot = call_slot().lock().await;
            if let Some(call) = slot.active.as_ref() {
                if let Some(s) = call.audio_stats().await {
                    tracing::info!(
                        sent = s.packets_sent,
                        received = s.packets_received,
                        muted = call.is_muted(),
                        "call audio"
                    );
                }
            } else if let Some(call) = slot.outgoing.as_ref() {
                if let Some(s) = call.stats().await {
                    tracing::info!(
                        sent = s.packets_sent,
                        received = s.packets_received,
                        undecryptable = s.packets_undecryptable,
                        muted = call.is_muted(),
                        audio_bytes = s.audio_bytes_sent,
                        played_peak = teams_cli::calling::audio::take_speaker_peak(),
                        mic = teams_cli::calling::audio::mic_level(),
                        mic_out = teams_cli::calling::audio::take_mic_out_peak(),
                        "call audio"
                    );
                }
            } else {
                return;
            }
        }
    });
}

/// Call health's samples of the call in progress.
/// The conversation the Forward and Share pickers' choices go to: a picked
/// chat or channel; one person's 1:1; several people's group chat (an
/// existing one with exactly those members, else a new one).
async fn picked_conversation(
    client: &TeamsClient,
    targets: &[serde_json::Value],
    group_chats: &[String],
) -> anyhow::Result<String> {
    let me = client
        .object_id()
        .ok_or_else(|| anyhow::anyhow!("not signed in"))?;
    let chats: Vec<&serde_json::Value> = targets.iter().filter(|t| t["kind"] == "chat").collect();
    let people: Vec<String> = targets
        .iter()
        .filter(|t| t["kind"] == "person")
        .filter_map(|t| t["oid"].as_str().map(str::to_string))
        .collect();
    if let Some(c) = chats.first() {
        return Ok(c["id"].as_str().unwrap_or_default().to_string());
    }
    if people.is_empty() {
        anyhow::bail!("Nobody to send to");
    }
    if people.len() == 1 {
        return api::ensure_one_on_one_chat(
            client,
            &format!("8:orgid:{me}"),
            &format!("8:orgid:{}", people[0]),
        )
        .await;
    }
    let mut want: Vec<String> = people
        .iter()
        .chain(std::iter::once(&me))
        .map(|o| format!("8:orgid:{}", o.to_ascii_lowercase()))
        .collect();
    want.sort();
    want.dedup();
    for chat in group_chats {
        if let Ok(mut members) = api::thread_member_ids(client, chat).await {
            members.sort();
            if members == want {
                return Ok(chat.clone());
            }
        }
    }
    api::create_group_chat(client, &want, "").await
}

/// Your group chats' ids (for finding an existing chat with exactly some
/// people).
fn group_chat_ids(chats_json: &str) -> Vec<String> {
    serde_json::from_str::<Vec<serde_json::Value>>(chats_json)
        .unwrap_or_default()
        .into_iter()
        .filter_map(|c| c.get("id").and_then(|i| i.as_str()).map(str::to_string))
        .filter(|i| i.ends_with("@thread.v2"))
        .collect()
}

fn health_sampler() -> &'static std::sync::Mutex<teams_cli::calling::call_health::Sampler> {
    static S: OnceLock<std::sync::Mutex<teams_cli::calling::call_health::Sampler>> = OnceLock::new();
    S.get_or_init(Default::default)
}

/// How many calls the Calls history shows.
const CALL_HISTORY_LIMIT: usize = 100;

/// Where downloads go: Settings ▸ Files and links' location, else
/// $XDG_DOWNLOAD_DIR, else ~/Downloads.
fn download_dir() -> Option<std::path::PathBuf> {
    if let Some(dir) = load_settings().get("downloadDir").and_then(|d| d.as_str()).filter(|d| !d.is_empty())
        && std::path::Path::new(dir).is_dir()
    {
        return Some(std::path::PathBuf::from(dir));
    }
    std::env::var_os("XDG_DOWNLOAD_DIR")
        .map(std::path::PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| std::path::PathBuf::from(h).join("Downloads")))
}

/// The camera chosen in Settings > Devices (a V4L2 path), else the default.
fn camera_device() -> Option<String> {
    load_settings()
        .get("cameraDevice")
        .and_then(|v| v.as_str())
        .filter(|d| d.starts_with("/dev/video") && d[10..].bytes().all(|b| b.is_ascii_digit()))
        .map(str::to_string)
}

/// Whether a pushed message gets a desktop notification, as Teams decides
/// by default: never your own, nor in the chat you're looking at; chat
/// messages unless you asked for mentions only; channel posts and muted
/// chats ("You're only notified of @Mentions") only when they mention you.
fn should_notify(
    mine: bool,
    open: bool,
    empty: bool,
    banners_on: bool,
    mentions_only: bool,
    mentions_needed: bool,
    mentioned: bool,
) -> bool {
    if mine || open || empty || !banners_on {
        return false;
    }
    mentioned || !(mentions_needed || mentions_only)
}

/// Settings ▸ Notifications and activity as OST honours them: the synced
/// ones from userPersonalSettings (toastSettings / soundsSettings, Teams'
/// defaults where unsaved) and this device's own.
#[derive(Debug, Clone, PartialEq)]
struct NotifyPrefs {
    mute_all: bool,
    allow_urgent_when_muted: bool,
    chat_banners: bool,
    personal_mention_banners: bool,
    previews: bool,
    during_calls: bool,
    sound: bool,
    sound_when_busy: bool,
    meet_now: bool,
    seconds: u32,
    flash: bool,
}

fn notify_prefs(settings_json: &str, local: &serde_json::Map<String, serde_json::Value>) -> NotifyPrefs {
    let all: serde_json::Value = serde_json::from_str(settings_json).unwrap_or_default();
    let ups = &all["props"]["userPersonalSettings"];
    let t = |k: &str| &ups["toastSettings"][k];
    let on_off = |v: &serde_json::Value, dflt: bool| v.as_str().map(|s| s == "On").unwrap_or(dflt);
    let flag = |v: &serde_json::Value, dflt: bool| v.as_bool().unwrap_or(dflt);
    let l = |k: &str| local.get(k).and_then(|v| v.as_str()).map(str::to_string);
    NotifyPrefs {
        mute_all: on_off(t("muteGenericNotifications"), false),
        allow_urgent_when_muted: l("allowUrgentWhenMuted").as_deref() == Some("true"),
        chat_banners: flag(t("Chat"), true),
        personal_mention_banners: flag(t("Mention_Person"), true) && flag(t("MentionInChat_Person_v2"), true),
        previews: on_off(t("ShowPreviewInToasts"), true),
        during_calls: !on_off(t("MuteNotificationsDuringMeetings"), false),
        sound: ups["soundsSettings"]["alertSound"].as_str() != Some("Off"),
        sound_when_busy: on_off(t("PlayNotificationSoundsWhenBusyOrInMeetings"), true),
        meet_now: flag(t("HuddleStartedNotification"), false),
        seconds: l("toastSeconds").and_then(|s| s.parse().ok()).unwrap_or(5),
        flash: l("flashTaskbar").as_deref() != Some("false"),
    }
}

/// Whether you muted the chat (the chat list's `muted`).
fn chat_muted(chats: &[serde_json::Value], id: &str) -> bool {
    chats
        .iter()
        .find(|c| c["id"].as_str() == Some(id))
        .and_then(|c| c["muted"].as_bool())
        .unwrap_or(false)
}

/// Teams' typing line (tmp_messages_typingIndicator_mf): "X is typing",
/// "X and Y are typing", "X, Y, and Z are typing", "X, Y, and N others
/// are typing" (N = count − 2).
/// Someone typing in the open chat.
#[derive(Debug, Clone)]
pub struct Typer {
    /// Their MRI (lowercase), else their name.
    key: String,
    name: String,
    until: std::time::Instant,
}

fn typing_text(names: &[String]) -> String {
    match names {
        [] => String::new(),
        [a] => format!("{a} is typing"),
        [a, b] => format!("{a} and {b} are typing"),
        [a, b, c] => format!("{a}, {b}, and {c} are typing"),
        [a, b, rest @ ..] => format!("{a}, {b}, and {} others are typing", rest.len()),
    }
}

/// What Teams does with a toast (async-apps-notifications 876340 `jt`).
#[derive(Debug, PartialEq, Eq)]
enum Toast {
    Show,
    /// Presenting: shown, but as "You have a new notification".
    Redacted,
    Drop,
}

/// Teams' toast rule by your own presence: urgent (or from a priority
/// contact) always shows, redacted while presenting; otherwise Presenting
/// and Do not disturb drop it. Busy doesn't.
fn toast_decision(availability: &str, presenting: bool, urgent: bool) -> Toast {
    if urgent {
        return if presenting {
            Toast::Redacted
        } else {
            Toast::Show
        };
    }
    if presenting || availability.eq_ignore_ascii_case("DoNotDisturb") {
        return Toast::Drop;
    }
    Toast::Show
}

/// Longest message text shown in a notification.
const NOTIFICATION_BODY_CHARS: usize = 200;

/// A typing indicator disappears this long after the last typing event.
const TYPING_TTL_SECS: u64 = 22;
/// Send our own typing indicator at most this often.
const TYPING_SEND_INTERVAL_SECS: u64 = 20;

/// How long an unanswered call rings before it counts as missed.
const RING_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(60);

/// How many chats to load per request.
const CHAT_LIMIT: usize = 50;

fn runtime() -> &'static tokio::runtime::Runtime {
    static RT: OnceLock<tokio::runtime::Runtime> = OnceLock::new();
    RT.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .enable_all()
            .build()
            .expect("failed to start the engine runtime")
    })
}

/// A short, single-line error for the status bar. Never includes tokens:
/// engine errors are built from endpoint error codes, not response bodies.
fn short_error(e: &anyhow::Error) -> String {
    let text = format!("{e:#}");
    let line = text.lines().next().unwrap_or_default();
    line.chars().take(200).collect()
}

async fn load_overview() -> anyhow::Result<(String, Vec<serde_json::Value>)> {
    let client = TeamsClient::new().await?;
    let my_oid = client.object_id().unwrap_or_default();
    let me = api::whoami_data(&client).await?;
    let chats = api::list_chats_data(&client, CHAT_LIMIT).await?;
    let favorites = api::messages::favorites(&client).await.unwrap_or_else(|e| {
        tracing::debug!("favorites unavailable: {}", short_error(&e));
        Vec::new()
    });
    let fav_rank = |id: &str| favorites.iter().position(|f| f == id);
    // Your own chat (Teams' "notes" thread), listed as "<you> (You)".
    let notes = chats.iter().find(|c| c.id == "48:notes");
    let mut list: Vec<serde_json::Value> = vec![json!({
        "id": "48:notes",
        "name": format!("{} (You)", me.display_name),
        "isGroup": false,
        "isSelf": true,
        "time": notes.and_then(|c| c.last_message_time.clone()),
        "sender": notes.and_then(|c| c.last_message_sender.clone()),
        "preview": notes.and_then(|c| c.last_message_preview.clone()),
        "previewSystem": notes.is_some_and(|c| c.last_message_system),
        "peerMri": format!("8:orgid:{my_oid}"),
        "favorite": fav_rank("48:notes").is_some(),
        "favoriteRank": fav_rank("48:notes"),
    })];
    let rest: Vec<_> = chats
        .iter()
        // 48:… threads are system streams (call logs, notifications,
        // mentions), not chats; Teams does not list them.
        .filter(|c| !c.id.starts_with("48:"))
        // Channels (…@thread.tacv2 / @thread.skype) are listed under their
        // team, not with the chats.
        .filter(|c| !c.id.ends_with("@thread.tacv2") && !c.id.ends_with("@thread.skype"))
        .map(|c| {
            json!({
                "id": c.id,
                "name": c.name,
                "isGroup": c.is_group,
                "time": c.last_message_time,
                "sender": c.last_message_sender,
                "preview": c.last_message_preview,
                "previewSystem": c.last_message_system,
                "liveCall": c.live_call,
                "muted": c.muted,
                "empty": c.empty,
                "hidden": c.hidden,
                "isCreator": c.is_creator,
                "meeting": c.id.starts_with("19:meeting_"),
                "peerMri": outgoing::callee_mri_for_chat(&c.id, &my_oid),
                "favorite": fav_rank(&c.id).is_some(),
                "favoriteRank": fav_rank(&c.id),
            })
        })
        .collect();
    list.extend(rest);
    Ok((me.display_name, list))
}

/// Messages deleted from this app since it started. Teams shows its
/// "This message has been deleted" placeholder only to the person who just
/// deleted it; once reloaded, deleted messages are simply gone.
fn deleted_here() -> &'static std::sync::Mutex<std::collections::HashSet<String>> {
    static SET: OnceLock<std::sync::Mutex<std::collections::HashSet<String>>> = OnceLock::new();
    SET.get_or_init(Default::default)
}

/// Where you had read each chat up to when you opened it. Teams keeps its
/// "Last read" line there for as long as the chat stays open, even after
/// the chat is marked read.
fn read_at_open() -> &'static std::sync::Mutex<HashMap<String, Option<u64>>> {
    static MAP: OnceLock<std::sync::Mutex<HashMap<String, Option<u64>>>> = OnceLock::new();
    MAP.get_or_init(Default::default)
}

fn cache_base() -> std::path::PathBuf {
    std::env::var_os("XDG_CACHE_HOME")
        .map(std::path::PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| std::path::PathBuf::from(h).join(".cache")))
        .unwrap_or_else(std::env::temp_dir)
        .join("ost")
}

/// Teams' emoticon catalogue, once loaded.
fn emoticon_catalog() -> &'static std::sync::RwLock<Option<std::sync::Arc<api::emoticons::Catalog>>>
{
    static C: OnceLock<std::sync::RwLock<Option<std::sync::Arc<api::emoticons::Catalog>>>> =
        OnceLock::new();
    C.get_or_init(Default::default)
}

/// Emoticon image URL → local file URL ("" while downloading or failed).
fn emoticon_files() -> &'static std::sync::Mutex<HashMap<String, String>> {
    static M: OnceLock<std::sync::Mutex<HashMap<String, String>>> = OnceLock::new();
    M.get_or_init(Default::default)
}

/// Messages being sent (Teams' send pipeline and offline queue), kept in
/// `$XDG_STATE_HOME/ost/outbox.json` so failed and queued sends survive a
/// restart.
fn outbox() -> &'static std::sync::Arc<api::outbox::Outbox> {
    static OUTBOX: OnceLock<std::sync::Arc<api::outbox::Outbox>> = OnceLock::new();
    OUTBOX.get_or_init(|| {
        let base = std::env::var_os("XDG_STATE_HOME")
            .map(std::path::PathBuf::from)
            .or_else(|| {
                std::env::var_os("HOME").map(|h| std::path::PathBuf::from(h).join(".local/state"))
            })
            .unwrap_or_else(std::env::temp_dir);
        api::outbox::Outbox::open(Some(base.join("ost").join("outbox.json")))
    })
}

/// Each chat's last timeline from the service, so the messages being sent
/// can be redrawn over it without reloading.
fn server_timelines() -> &'static std::sync::Mutex<HashMap<String, Vec<api::messages::MessageView>>>
{
    static MAP: OnceLock<std::sync::Mutex<HashMap<String, Vec<api::messages::MessageView>>>> =
        OnceLock::new();
    MAP.get_or_init(Default::default)
}

/// The open chat's pinned banner (`pinned_json`), per chat.
fn pinned_banner() -> &'static std::sync::Mutex<(String, serde_json::Value)> {
    static P: OnceLock<std::sync::Mutex<(String, serde_json::Value)>> = OnceLock::new();
    P.get_or_init(Default::default)
}

/// The open chat's pinned message ids, newest first.
fn pinned_order() -> &'static std::sync::Mutex<(String, Vec<String>)> {
    static P: OnceLock<std::sync::Mutex<(String, Vec<String>)>> = OnceLock::new();
    P.get_or_init(Default::default)
}

/// On-demand translations by (chat, message): the translation and whether
/// it is shown (Teams caches it; See original only hides it).
type Translated = HashMap<(String, String), (api::msgactions::Translation, bool)>;
fn translations() -> &'static std::sync::Mutex<Translated> {
    static T: OnceLock<std::sync::Mutex<Translated>> = OnceLock::new();
    T.get_or_init(Default::default)
}

/// Show shown translations in a timeline.
fn apply_translations(chat_id: &str, timeline: &mut [api::messages::MessageView]) {
    let t = translations().lock().unwrap();
    for m in timeline.iter_mut() {
        match t.get(&(chat_id.to_string(), m.id.clone())) {
            Some((tr, true)) if tr.status == "Done" => {
                m.html = api::messages::sanitize_html(&tr.content);
                m.text = api::strip_html(&tr.content).trim().to_string();
                m.translated = true;
                m.translated_from = tr.detected_language.clone();
            }
            Some((_, true)) => m.translation_failed = true,
            _ => {}
        }
    }
}

/// A chat's timeline with its messages being sent placed in it; those the
/// service already has leave the outbox.
fn with_lies(
    chat_id: &str,
    mut timeline: Vec<api::messages::MessageView>,
) -> Vec<api::messages::MessageView> {
    apply_translations(chat_id, &mut timeline);
    let lies = outbox().for_conversation(chat_id);
    let arrived = api::outbox::merge_lies(&mut timeline, &lies);
    outbox().arrived(&arrived);
    timeline
}

/// A window's conversation: "win:<channel>" is a whole channel's window (its
/// timeline kept apart from the open chat's), else "<channel>;messageid=…".
/// A chat's conversation id ("19:…@thread.v2", "19:…@unq.gbl.spaces",
/// meeting chats), as a chat window takes it.
fn is_chat_id(id: &str) -> bool {
    // (Your own notes chat, 48:notes, is a chat too.)
    id == "48:notes" || (id.starts_with("19:") && id.contains('@') && !id.contains(';') && !id.ends_with("@thread.tacv2"))
}

fn window_conversation(key: &str) -> &str {
    key.strip_prefix("win:").unwrap_or(key)
}


/// The post composer's fields for the next channel post.
#[derive(Debug, Clone, Default)]
struct NextPost {
    subject: String,
    title: String,
    theme: String,
    /// The banner picture: the cropped PNG and its size.
    image: String,
    image_w: u32,
    image_h: u32,
    /// A message in a Threads-layout channel (no post type).
    threads: bool,
}

impl NextPost {
    fn from_json(s: &str) -> Option<NextPost> {
        let v: serde_json::Value = serde_json::from_str(s).ok()?;
        let f = |k: &str| v.get(k).and_then(|x| x.as_str()).unwrap_or_default().to_string();
        let n = |k: &str| v.get(k).and_then(|x| x.as_u64()).unwrap_or(0) as u32;
        Some(NextPost {
            subject: f("subject"),
            title: f("title"),
            theme: f("theme"),
            image: f("image"),
            image_w: n("imageWidth"),
            image_h: n("imageHeight"),
            threads: v.get("threads").and_then(|x| x.as_bool()).unwrap_or(false),
        })
    }
}

/// The channel a window's key belongs to.
fn window_channel(key: &str) -> &str {
    window_conversation(key).split(';').next().unwrap_or_default()
}

/// A thread window's messages with what is being sent to it; translations
/// are kept per channel (Teams translates the channel's messages).
fn with_thread_lies(
    thread: &str,
    mut timeline: Vec<api::messages::MessageView>,
) -> Vec<api::messages::MessageView> {
    apply_translations(window_channel(thread), &mut timeline);
    let lies = outbox().for_conversation(window_conversation(thread));
    let arrived = api::outbox::merge_lies(&mut timeline, &lies);
    outbox().arrived(&arrived);
    timeline
}

/// A channel post and its replies ("<channel>;messageid=<post>", the reply
/// chain Teams reads), with saved, pinned and followed marks and pictures,
/// into server_timelines.
async fn load_thread(thread: &str) -> anyhow::Result<()> {
    let client = TeamsClient::new().await?;
    let channel = window_channel(thread).to_string();
    let page = api::messages::read_timeline_page(&client, window_conversation(thread), 200, None).await?;
    let mut timeline = page.messages;
    {
        let here = deleted_here().lock().unwrap();
        timeline.retain(|m| !m.deleted || here.contains(&m.id));
    }
    let (rc, pinned) = tokio::join!(
        api::msgactions::rc_metadata(&client, &channel),
        api::msgactions::pinned_ids(&client, &channel),
    );
    let (saved, follow, horizons) = rc.unwrap_or_default();
    let pinned = pinned.unwrap_or_default();
    api::messages::apply_following(&mut timeline, &follow);
    api::messages::apply_thread_horizons(&mut timeline, &horizons);
    for m in timeline.iter_mut() {
        m.saved = saved.contains(&m.id);
        m.pinned = pinned.contains(&m.id);
    }
    for img in timeline.iter_mut().flat_map(|m| m.images.iter_mut()) {
        match cached_image(&client, img).await {
            Ok(path) => img.local_path = format!("file://{}", path.display()),
            Err(e) => tracing::warn!("image download failed: {}", short_error(&e)),
        }
    }
    for m in timeline.iter_mut() {
        localize_banner(&client, m).await;
        localize_custom_emoji(&client, m).await;
        localize_emoticons(m).await;
        localize_edit_images(m);
    }
    server_timelines()
        .lock()
        .unwrap()
        .insert(thread.to_string(), timeline);
    Ok(())
}

/// Each chat's older pages loaded so far (scrolling up), and the token
/// for the page before them; none once the start of the chat is reached.
type OlderPages = (Vec<api::messages::MessageView>, Option<String>);
fn older_pages() -> &'static std::sync::Mutex<HashMap<String, OlderPages>> {
    static MAP: OnceLock<std::sync::Mutex<HashMap<String, OlderPages>>> = OnceLock::new();
    MAP.get_or_init(Default::default)
}

/// A chat's timeline: the newest page, under the older pages already
/// loaded; with the newest message's ids and whether older ones remain.
async fn load_messages(
    chat_id: String,
) -> anyhow::Result<(String, Option<(String, String)>, bool)> {
    let client = TeamsClient::new().await?;
    let known = read_at_open().lock().unwrap().get(&chat_id).copied();
    let opened_at = match known {
        Some(h) => h,
        None => {
            let h = api::messages::my_read_horizon(&client, &chat_id)
                .await
                .unwrap_or_else(|e| {
                    tracing::debug!("read horizon unavailable: {}", short_error(&e));
                    None
                });
            read_at_open().lock().unwrap().insert(chat_id.clone(), h);
            h
        }
    };
    let (page, facts) = tokio::join!(
        api::messages::read_timeline_page(&client, &chat_id, api::messages::PAGE_SIZE, None),
        api::messages::conversation_facts(&client, &chat_id),
    );
    let page = page?;
    let cleared = facts
        .unwrap_or_else(|e| {
            tracing::debug!("conversation facts unavailable: {}", short_error(&e));
            Default::default()
        })
        .cleared_ms;
    let (mut timeline, has_older) = {
        let mut map = older_pages().lock().unwrap();
        let entry = map
            .entry(chat_id.clone())
            .or_insert_with(|| (Vec::new(), page.older.clone()));
        (
            api::messages::merge_pages(&entry.0, page.messages),
            entry.1.is_some(),
        )
    };
    api::messages::mark_first_unread(&mut timeline, opened_at);
    {
        let here = deleted_here().lock().unwrap();
        timeline.retain(|m| !m.deleted || here.contains(&m.id));
    }
    // Remove chat history: what came before isn't shown (Teams'
    // MessageIdLessThanClearHistoryTime).
    if let Some(t) = cleared {
        timeline.retain(|m| m.id.parse::<u64>().map_or(true, |id| id > t));
    }
    // Read horizons, saved messages and pins, as Teams loads them.
    let (horizon, rc, pinned) = tokio::join!(
        api::messages::peer_read_horizon(&client, &chat_id),
        api::msgactions::rc_metadata(&client, &chat_id),
        api::msgactions::pinned_ids(&client, &chat_id),
    );
    let (saved, follow, horizons) = rc.unwrap_or_default();
    match horizon {
        Ok(h) => api::messages::apply_seen(&mut timeline, h),
        Err(e) => tracing::debug!("read horizons unavailable: {}", short_error(&e)),
    }
    let pinned = pinned.unwrap_or_default();
    api::messages::apply_following(&mut timeline, &follow);
    api::messages::apply_thread_horizons(&mut timeline, &horizons);
    for m in timeline.iter_mut() {
        m.saved = saved.contains(&m.id);
        m.pinned = pinned.contains(&m.id);
    }
    // Teams' banner shows the newest pin; fetch it if it isn't loaded.
    let banner = match pinned.first() {
        None => serde_json::Value::Null,
        Some(id) => {
            let shown = timeline.iter().find(|m| &m.id == id).cloned();
            let m = match shown {
                Some(m) => Some(m),
                None => api::messages::read_message(&client, &chat_id, id)
                    .await
                    .ok(),
            };
            match m {
                Some(m) => {
                    json!({ "id": m.id, "sender": m.sender, "sender_mri": m.sender_mri, "text": m.text, "time": m.time, "count": pinned.len() })
                }
                None => serde_json::Value::Null,
            }
        }
    };
    *pinned_banner().lock().unwrap() = (chat_id.clone(), banner);
    *pinned_order().lock().unwrap() = (chat_id.clone(), pinned);
    for img in timeline.iter_mut().flat_map(|m| m.images.iter_mut()) {
        match cached_image(&client, img).await {
            Ok(path) => img.local_path = format!("file://{}", path.display()),
            Err(e) => tracing::warn!("image download failed: {}", short_error(&e)),
        }
    }
    for m in timeline.iter_mut() {
        localize_banner(&client, m).await;
        localize_custom_emoji(&client, m).await;
        localize_emoticons(m).await;
        localize_edit_images(m);
    }
    let last_id = timeline
        .iter()
        .rev()
        .find(|m| m.kind == "message")
        .map(|m| (m.id.clone(), m.client_message_id.clone()));
    server_timelines()
        .lock()
        .unwrap()
        .insert(chat_id.clone(), timeline.clone());
    let timeline = with_lies(&chat_id, timeline);
    Ok((serde_json::to_string(&timeline)?, last_id, has_older))
}

/// Fetch who waits in the lobby of the current meeting into callLobbyJson.
async fn refresh_lobby(qt: cxx_qt::CxxQtThread<qobject::Backend>) {
    let people = match call_slot().lock().await.outgoing.as_ref() {
        Some(call) => call.lobby().await,
        None => return,
    };
    match people {
        Ok(list) => {
            let json = serde_json::to_string(
                &list
                    .iter()
                    .map(|p| json!({ "id": p.id, "name": p.name, "suspected": p.suspected }))
                    .collect::<Vec<_>>(),
            )
            .unwrap_or_else(|_| "[]".into());
            tracing::info!(waiting = list.len(), "lobby");
            let _ = qt.queue(move |mut this| {
                this.as_mut()
                    .set_call_lobby_json(QString::from(json.as_str()))
            });
        }
        Err(e) => tracing::warn!("lobby list failed: {}", short_error(&e)),
    }
}

/// A call event arrived: ring for a new invitation; anything else about
/// the current call is logged by shape (never by content) so call-end
/// signalling can be recognised.
/// The source ids of one of OST's own call events (`path`), if `json` is
/// one.
fn call_event_source_ids(json: &str, path: &str) -> Option<Vec<i64>> {
    let v = serde_json::from_str::<serde_json::Value>(json).ok()?;
    (v["callAgentPath"] == path).then(|| {
        v["body"]["sourceIds"]
            .as_array()
            .map(|a| a.iter().filter_map(serde_json::Value::as_i64).collect())
            .unwrap_or_default()
    })
}

/// Make sure the meeting's recorder is in the call, inviting it as Teams
/// does when it isn't, and wait (up to 20 s) for the roster to list it with
/// its command URL.
async fn ensure_recorder(meeting: &teams_cli::calling::recorder::Meeting) -> anyhow::Result<()> {
    {
        let slot = call_slot().lock().await;
        let call = slot.outgoing.as_ref().context("Not in a call")?;
        if call.has_recorder() {
            return Ok(());
        }
        call.add_recorder(meeting).await?;
    }
    for _ in 0..80 {
        tokio::time::sleep(std::time::Duration::from_millis(250)).await;
        if call_slot().lock().await.outgoing.as_ref().is_some_and(|c| c.has_recorder()) {
            tracing::info!("the meeting's recorder joined");
            return Ok(());
        }
    }
    anyhow::bail!("The meeting's recorder didn't join")
}

async fn on_call_event(qt: &cxx_qt::CxxQtThread<qobject::Backend>, json: &str) {
    // An event for a call we moved out of (a meeting left for a breakout
    // room, or the room left for the meeting) is that call's, not ours.
    if json.contains("\"callTag\"")
        && let Some(tag) = serde_json::from_str::<serde_json::Value>(json)
            .ok()
            .and_then(|v| v["callTag"].as_str().map(str::to_string))
        && call_slot().lock().await.left_tags.contains(&tag)
    {
        tracing::debug!(event = %json.chars().take(300).collect::<String>(), "event of a call we moved out of");
        return;
    }
    // The held main meeting's events: its rooms (managed from the room
    // too) and its end; the room's window shows nothing else of it.
    if json.contains("\"callTag\"")
        && let Some(tag) = serde_json::from_str::<serde_json::Value>(json)
            .ok()
            .and_then(|v| v["callTag"].as_str().map(str::to_string))
    {
        let mut slot = call_slot().lock().await;
        if slot.held_main.as_ref().is_some_and(|(c, _, _)| c.call_tag() == tag) {
            if teams_cli::calling::incoming::is_call_end_event(json) {
                tracing::info!("the held main meeting ended");
                slot.held_main = None;
                drop(slot);
                let _ = qt.queue(|mut this| this.as_mut().set_call_held_meeting_json(QString::default()));
            } else if let Some(rooms) = teams_cli::calling::breakout::all_rooms(json) {
                drop(slot);
                let text = serde_json::to_string(&rooms).unwrap_or_default();
                let _ = qt.queue(move |mut this| this.as_mut().set_call_breakout_all_json(QString::from(text.as_str())));
            }
            return;
        }
    }
    // The chat call we watch: its roster changes, or it ends.
    if json.contains("\"callAgentPath\":\"subscription/") {
        tracing::debug!(event = %json.chars().take(1500).collect::<String>(), "watched call event");
        let mut w = watched_call().lock().await;
        let ended = json.contains("subscription/conversationEnd");
        let roster = match w.as_mut() {
            Some(sub) if ended => {
                sub.roster.clear();
                Some("[]".to_string())
            }
            Some(sub) => sub.apply(json).then(|| live_roster_json(sub)),
            None => None,
        };
        if let Some(json) = roster {
            let _ = qt.queue(move |mut this| {
                this.as_mut()
                    .set_chat_live_roster_json(QString::from(json.as_str()))
            });
        }
        return;
    }
    if let Some(start) = teams_cli::calling::incoming::meeting_start(json) {
        tracing::info!(thread = %start.thread_id, "meeting started in a chat");
        let qt2 = qt.clone();
        let _ = qt.queue(move |mut this| this.as_mut().notify_meeting_start(start, qt2));
        return;
    }
    // Meeting reactions: show them on the sender's tile.
    if let Some(reactions) = teams_cli::calling::roster::meeting_reactions(json) {
        for (mri, name) in reactions {
            let _ = qt.queue(move |this| {
                this.meeting_reaction(QString::from(mri.as_str()), QString::from(name.as_str()))
            });
        }
        return;
    }
    // The meeting's speech recognition (the Transcript pane).
    if json.contains("\"callAgentPath\":\"ost/transcript/\"") {
        let rows = serde_json::from_str::<serde_json::Value>(json)
            .ok()
            .and_then(|v| v.get("body").map(teams_cli::calling::transcript::from_live))
            .unwrap_or_default();
        let captions = serde_json::from_str::<serde_json::Value>(json)
            .ok()
            .and_then(|v| v.get("body").map(teams_cli::calling::transcript::results_from_live))
            .unwrap_or_default();
        if !rows.is_empty() || !captions.is_empty() {
            let _ = qt.queue(move |mut this| {
                if !captions.is_empty() && this.rust().call_captions_on {
                    this.as_mut().show_captions(captions);
                }
                if !rows.is_empty() {
                    this.show_transcript(rows, false);
                }
            });
        }
        return;
    }
    // Someone's real-time text (Teams' RTT on the data channel).
    if json.contains("\"callAgentPath\":\"ost/rtt/\"") {
        let body = serde_json::from_str::<serde_json::Value>(json)
            .ok()
            .and_then(|v| v.get("body").cloned());
        let source = body.as_ref().and_then(|b| b.get("sourceId")?.as_u64());
        let text = body.as_ref().and_then(|b| b.get("s")?.as_str().map(str::to_string));
        if let (Some(source), Some(text)) = (source.and_then(|s| u32::try_from(s).ok()), text) {
            let own = call_slot().lock().await.outgoing.as_ref().and_then(|c| c.data_source_id());
            let _ = qt.queue(move |mut this| this.as_mut().receive_rtt(source, text, own));
        }
        return;
    }
    // The media processor asks for a stream we send (someone started
    // watching our screen): its limits, and a keyframe.
    let requests = teams_cli::calling::meeting_media::video_control_requests(json);
    if !requests.is_empty() {
        if let Some(call) = call_slot().lock().await.outgoing.as_ref() {
            for (source, params) in &requests {
                tracing::info!(source, params, "video control request");
                call.control_video(*source, params);
            }
        }
        return;
    }
    // Who speaks now: the people whose audio sources are in the mix.
    if let Some(ids) = call_event_source_ids(json, "ost/activeSpeakers/") {
        let _ = qt.queue(move |mut this| {
            let mris: Vec<&str> = this
                .rust()
                .roster
                .iter()
                .filter(|p| p.audio_source.is_some_and(|a| ids.contains(&a)))
                .map(|p| p.id.as_str())
                .collect();
            let json = serde_json::to_string(&mris).unwrap_or_else(|_| "[]".into());
            if this.rust().call_speaking_json.to_string() != json {
                tracing::debug!(speaking = %json, "voice levels");
                this.as_mut()
                    .set_call_speaking_json(QString::from(json.as_str()));
            }
        });
        return;
    }
    // The media processor's dominant speaker: whose audio source it is.
    if let Some(ids) = call_event_source_ids(json, "ost/dominantSpeakers/") {
        let first = ids.first().copied();
        let _ = qt.queue(move |mut this| {
            let mri = first
                .and_then(|id| {
                    this.rust()
                        .roster
                        .iter()
                        .find(|p| p.audio_source == Some(id))
                })
                .map(|p| p.id.clone())
                .unwrap_or_default();
            if this.rust().call_speaker_mri.to_string() != mri {
                this.as_mut()
                    .set_call_speaker_mri(QString::from(mri.as_str()));
            }
        });
        return;
    }
    // The lobby count changed: ask who waits there (Teams does the same).
    if teams_cli::calling::roster::lobby_count(json).is_some() {
        let qt2 = qt.clone();
        runtime().spawn(async move { refresh_lobby(qt2).await });
    }
    // The breakout room we're in (closed, may we go back, where to).
    if json.contains("breakoutRoomProperties")
        && let Some(state) = teams_cli::calling::breakout::room_state(json)
    {
        let text = serde_json::to_string(&state).unwrap_or_default();
        tracing::info!(closed = state.closed, allow_return = state.allow_return, "in a breakout room");
        let _ = qt.queue(move |mut this| this.as_mut().set_call_breakout_room_json(QString::from(text.as_str())));
    }
    // The meeting's rooms, as its organizer sees them.
    if json.contains("allBreakoutRooms")
        && let Some(rooms) = teams_cli::calling::breakout::all_rooms(json)
    {
        let text = serde_json::to_string(&rooms).unwrap_or_default();
        tracing::info!(rooms = rooms.len(), open = rooms.iter().filter(|r| r.open).count(), "meeting breakout rooms");
        let _ = qt.queue(move |mut this| this.as_mut().set_call_breakout_all_json(QString::from(text.as_str())));
    }
    // Breakout rooms assigned to us (opened, closed, changed).
    if json.contains("breakoutDetails")
        && let Some(rooms) = teams_cli::calling::breakout::assigned_rooms(json)
    {
        let text = serde_json::to_string(&rooms).unwrap_or_default();
        tracing::info!(rooms = rooms.len(), open = rooms.iter().filter(|r| r.open).count(), "breakout rooms");
        let _ = qt.queue(move |mut this| this.as_mut().set_call_breakout_json(QString::from(text.as_str())));
    }
    // Waiting in a lobby: once an organizer writes, the lobby chat thread
    // arrives (activeModalities.groupChat.lobbyThreadId) and Teams offers
    // its Lobby chat.
    if json.contains("lobbyThreadId")
        && let Ok(v) = serde_json::from_str::<serde_json::Value>(json)
        && let Some(id) = v.pointer("/body/activeModalities/groupChat/lobbyThreadId").and_then(|t| t.as_str()).filter(|t| t.starts_with("19:"))
    {
        let id = id.to_string();
        tracing::info!("lobby chat thread from the call");
        let _ = qt.queue(move |mut this| {
            if this.rust().call_lobby_thread.to_string() != id {
                this.as_mut().set_call_lobby_thread(QString::from(id.as_str()));
            }
        });
    }
    // Our leg moved to another call (the lobby handed us to the meeting):
    // hang-up and hold now go to the new leg.
    if let Some(links) = teams_cli::calling::outgoing::leg_retarget(json)
        && let Some(call) = call_slot().lock().await.outgoing.as_mut()
    {
        call.retarget(links);
    }
    // Admitted from the lobby: the call modality arrives with the
    // conversation's links; Teams then shows the meeting.
    if let Some(update) = teams_cli::calling::outgoing::lobby_admission(json) {
        let admitted = match call_slot().lock().await.outgoing.as_mut() {
            Some(call) if call.in_lobby() => {
                call.admit_from_lobby(&update);
                Some((call.capability(), call.can_send_video(), call.can_share()))
            }
            _ => None,
        };
        if let Some((cap, can_video, can_share)) = admitted {
            let _ = qt.queue(move |mut this| {
                this.as_mut().show_capability(cap, false);
                this.as_mut().set_call_can_video(can_video);
                this.as_mut().set_call_can_share(can_share);
                this.as_mut().set_call_state(QString::from("connected"));
            });
        }
    }
    // The meeting's call recorder started or stopped its transcript
    // (Teams' AI indicator turns on and off with it).
    if json.contains("conversation/rosterUpdate")
        && let Ok(v) = serde_json::from_str::<serde_json::Value>(json)
    {
        let changed = call_slot()
            .lock()
            .await
            .outgoing
            .as_mut()
            .and_then(|call| call.apply_processing(&v).then(|| call.processing()));
        if let Some(p) = changed {
            tracing::info!(?p, "call recorder processing changed");
            let _ = qt.queue(move |mut this| this.as_mut().show_processing(p));
        }
    }
    // The meeting locked or unlocked, or changed what attendees may do.
    if json.contains("conversationUpdate") || json.contains("meetingCapability") {
        tracing::debug!(event = %json.chars().take(3000).collect::<String>(), "conversation update");
        if let Ok(v) = serde_json::from_str::<serde_json::Value>(json) {
            let changed = call_slot()
                .lock()
                .await
                .outgoing
                .as_mut()
                .and_then(|call| call.apply_capability(&v).then(|| call.capability()));
            if let Some(cap) = changed {
                tracing::info!(?cap, "meeting capability changed");
                let _ = qt.queue(move |mut this| this.as_mut().show_capability(cap, true));
            }
            // The meeting timer changed (someone's start, pause, …).
            let timers = call_slot()
                .lock()
                .await
                .outgoing
                .as_mut()
                .and_then(|call| call.apply_timer(&v).then(|| call.timers().clone()));
            if let Some(t) = timers {
                tracing::info!(state = t.adhoc.state(), sequence = t.sequence, "meeting timer changed");
                let _ = qt.queue(move |mut this| {
                    // Teams' clock skew: measured from live updates.
                    if let Some(stamp) = t.stamp_ms {
                        this.as_mut().rust_mut().timer_skew_ms = chrono::Utc::now().timestamp_millis() - stamp;
                    }
                    this.as_mut().show_timers(t, true);
                });
            }
        }
    }
    // The meeting muting (or unmuting) us: Teams mutes you when the
    // meeting does, and opens the mic once a requested unmute goes through.
    {
        let slot = call_slot().lock().await;
        if let Some(call) = slot.outgoing.as_ref()
            && let Some(id) = call.endpoint_id()
            && let Some(server_muted) = teams_cli::calling::roster::own_server_muted(json, id)
        {
            let was = call.is_server_muted();
            call.set_server_muted(server_muted);
            if server_muted != was {
                tracing::info!(server_muted, "the meeting changed our mute");
            }
            drop(slot);
            let _ = qt.queue(move |mut this| {
                if this.rust().call_muted_by_meeting != server_muted {
                    this.as_mut().set_call_muted_by_meeting(server_muted);
                }
                // Teams alerts only when it mutes you while you're unmuted.
                if server_muted && !this.rust().call_muted && this.rust().call_has_audio {
                    let n = this.rust().call_muted_remotely + 1;
                    this.as_mut().set_call_muted_remotely(n);
                }
                if server_muted && !this.rust().call_muted {
                    this.as_mut().set_call_muted(true);
                    runtime().spawn(async {
                        if let Some(call) = call_slot().lock().await.outgoing.as_ref() {
                            call.set_muted(true);
                        }
                    });
                } else if !server_muted && this.rust().unmute_pending {
                    this.as_mut().rust_mut().unmute_pending = false;
                    this.as_mut().set_call_muted(false);
                    // Then our own endpoint state says unmuted too.
                    runtime().spawn(async {
                        if let Some(call) = call_slot().lock().await.outgoing.as_ref() {
                            call.set_muted(false);
                            if let Err(e) = call.publish_mute(false).await {
                                tracing::warn!("mute state: {}", short_error(&e));
                            }
                        }
                    });
                }
            });
        }
    }
    if let Some(delta) = teams_cli::calling::roster::roster_delta(json) {
        tracing::info!(changes = delta.len(), "roster update");
        let _ = qt.queue(move |mut this| {
            if !this.rust().call_meeting {
                // A 1:1 call: the roster tells when the other person holds.
                let me = this.rust().user_mri.to_string().to_ascii_lowercase();
                let changed: Vec<_> = delta
                    .iter()
                    .filter(|p| p.id != me && p.id.starts_with("8:"))
                    .collect();
                if let Some(p) = changed.first() {
                    let held = p.active && p.on_hold;
                    if held != this.rust().call_held_by_peer {
                        tracing::info!(held, "peer hold state");
                        this.as_mut().set_call_held_by_peer(held);
                    }
                }
                return;
            }
            let me = this.rust().user_mri.to_string().to_ascii_lowercase();
            // Our own hand as the meeting sees it (also lowered by others).
            if let Some(p) = delta.iter().find(|p| p.id == me) {
                let raised = p.hand.is_some();
                if raised != this.rust().call_hand_raised {
                    this.as_mut().set_call_hand_raised(raised);
                }
                let id = p.hand.clone().filter(|h| h != "raised");
                runtime().spawn(async move {
                    if let Some(call) = call_slot().lock().await.outgoing.as_mut() {
                        call.note_hand(id);
                    }
                });
            }
            this.as_mut().apply_roster(delta);
        });
        return;
    }
    if let Some(call) = IncomingCall::parse(json) {
        tracing::debug!(payload = %json.chars().take(6000).collect::<String>(), "incoming call payload");
        let mut slot = call_slot().lock().await;
        if slot.ringing.is_some() || slot.active.is_some() {
            tracing::info!("second incoming call while busy; ignoring");
            return;
        }
        let peer = call.caller_name();
        let peer_id = call.caller_id().unwrap_or_default();
        let video = call.has_video();
        let call_id = call.call_id();
        slot.ringing = Some(call);
        drop(slot);
        tracing::info!(video, "incoming call");
        let _ = qt.queue(move |mut this| {
            this.as_mut().set_call_peer(QString::from(peer.as_str()));
            this.as_mut()
                .set_call_peer_id(QString::from(peer_id.as_str()));
            this.as_mut().set_call_video_offered(video);
            this.as_mut().set_call_meeting(false);
            this.as_mut().set_call_scheduled(false);
            this.as_mut().set_call_state(QString::from("ringing"));
        });
        // Teams web's calls only say they're video calls in the full
        // invitation: fetch it while ringing (an Accept meanwhile waits).
        if !video {
            let (qt, call_id) = (qt.clone(), call_id.clone());
            runtime().spawn(async move {
                let Ok(auth) = CallAuth::load().await else {
                    return;
                };
                let mut slot = call_slot().lock().await;
                let Some(call) = slot.ringing.as_mut().filter(|c| c.call_id() == call_id) else {
                    return;
                };
                let video = auth.probe_video(call).await;
                drop(slot);
                tracing::info!(video, "incoming call probed");
                if video {
                    let _ = qt.queue(move |mut this| this.as_mut().set_call_video_offered(true));
                }
            });
        }
        // Stop ringing if nobody answers.
        let qt = qt.clone();
        runtime().spawn(async move {
            tokio::time::sleep(RING_TIMEOUT).await;
            let mut slot = call_slot().lock().await;
            if slot.ringing.as_ref().map(|c| c.call_id()) == Some(call_id) {
                slot.ringing = None;
                drop(slot);
                tracing::info!("call missed");
                let _ = qt.queue(|mut this| this.as_mut().end_call_ui());
            }
        });
        return;
    }
    if let Some(reply) = teams_cli::calling::incoming::reoffer_reply(json)
        && reoffer_reply(qt, reply).await
    {
        return;
    }
    if teams_cli::calling::incoming::is_renegotiation_event(json) {
        // Hold, resume or a camera change from the other side: answer it,
        // or Teams drops the call.
        let Ok(event) = serde_json::from_str::<serde_json::Value>(json) else {
            return;
        };
        let mut guard = call_slot().lock().await;
        let slot = &mut *guard;
        let result = match (slot.active.as_mut(), slot.outgoing.as_mut()) {
            (Some(call), _) => match CallAuth::load().await {
                Ok(auth) => call.answer_renegotiation(&auth, &event).await,
                Err(e) => Err(e),
            },
            (None, Some(call)) => call.answer_renegotiation(&event).await,
            _ => return,
        };
        let slot = guard;
        drop(slot);
        match result {
            Ok(held) => {
                tracing::info!(held, "re-offer answered");
                let _ = qt.queue(move |mut this| this.as_mut().set_call_held_by_peer(held));
            }
            Err(e) => tracing::warn!("re-offer not answered: {}", short_error(&e)),
        }
        return;
    }
    if let Some(outcome) = teams_cli::calling::incoming::transfer_outcome(json) {
        match outcome {
            Ok(()) => {
                // They took the call: ours is over.
                tracing::info!("call transferred");
                let mut slot = call_slot().lock().await;
                slot.active = None;
                slot.outgoing = None;
                drop(slot);
                let _ = qt.queue(|mut this| {
                    this.as_mut()
                        .set_status_text(QString::from("Call transferred"));
                    this.as_mut().end_call_ui();
                });
            }
            Err(phrase) => {
                tracing::info!("transfer failed");
                let _ = qt.queue(move |mut this| {
                    this.as_mut().set_status_text(QString::from(
                        format!("Transfer failed: {phrase}").as_str(),
                    ))
                });
            }
        }
        return;
    }
    if let Some(held) = teams_cli::calling::incoming::retarget_hold(json) {
        tracing::info!(held, "call retargeted");
        // Only a music bot says "held"; the roster tells when it ends.
        if held {
            let _ = qt.queue(move |mut this| this.as_mut().set_call_held_by_peer(true));
        }
        return;
    }
    if teams_cli::calling::incoming::is_call_end_event(json) {
        tracing::debug!(payload = %json, "call end payload");
        // The end of a meeting we moved out of (to a breakout room or
        // back) is not the end of the one we're in.
        let ended_id = serde_json::from_str::<serde_json::Value>(json)
            .ok()
            .and_then(|v| v.pointer("/body/debugContent/callId").and_then(|c| c.as_str()).map(str::to_string));
        if let Some(id) = ended_id {
            let mut slot = call_slot().lock().await;
            if slot.moved_from.as_ref().is_some_and(|c| c.call_id() == id) {
                slot.moved_from = None;
            }
            if slot.left_calls.contains(&id) {
                tracing::info!("a meeting we moved out of ended");
                return;
            }
        }
        // Denied, not let in, or removed: Teams keeps the window on its
        // retry screen saying so.
        let reason = teams_cli::calling::incoming::end_reason(json);
        if let Some(r) = reason {
            tracing::info!(reason = r.key(), "call ended for a reason");
            let _ = qt.queue(move |mut this| this.as_mut().set_call_end_reason(QString::from(r.key())));
        }
        let mut slot = call_slot().lock().await;
        let was_ringing = slot.ringing.take().is_some();
        // The other side ended it: drop media without signalling an end.
        let was_active = slot.active.take().is_some() || slot.outgoing.take().is_some();
        drop(slot);
        if was_ringing || was_active {
            tracing::info!(was_ringing, was_active, "call ended by the other side");
            let _ = qt.queue(|mut this| this.as_mut().end_call_ui());
        }
        return;
    }
    fn keys(v: &serde_json::Value, prefix: &str, depth: usize, out: &mut Vec<String>) {
        if let Some(o) = v.as_object() {
            for (k, child) in o {
                let path = if prefix.is_empty() {
                    k.clone()
                } else {
                    format!("{prefix}.{k}")
                };
                out.push(path.clone());
                if depth > 0 {
                    keys(child, &path, depth - 1, out);
                }
            }
        }
    }
    let mut shape = Vec::new();
    if let Ok(v) = serde_json::from_str::<serde_json::Value>(json) {
        keys(&v, "", 4, &mut shape);
    }
    tracing::info!(?shape, "call event");
    tracing::debug!(payload = %json, "call event payload");
}

/// Read (and with `changes`, first save) the meeting's options for Teams'
/// Controls menu, into call_controls_json.
async fn load_controls(
    qt: cxx_qt::CxxQtThread<qobject::Backend>,
    link: teams_cli::calling::outgoing::MeetingLink,
    changes: Vec<(String, serde_json::Value)>,
) {
    let (tenant, organizer) = (link.tenant_id.clone().unwrap_or_default(), link.organizer_id.clone().unwrap_or_default());
    let result = async {
        let client = TeamsClient::new().await?;
        if changes.is_empty() {
            api::meeting_options::get(&client, &tenant, &organizer, &link.thread_id, &link.message_id).await
        } else {
            let c: Vec<(&str, serde_json::Value)> = changes.iter().map(|(n, v)| (n.as_str(), v.clone())).collect();
            api::meeting_options::set(&client, &tenant, &organizer, &link.thread_id, &link.message_id, &c).await
        }
    }
    .await;
    let json = match result {
        Ok(o) => {
            tracing::info!(count = o.options.len(), invitees = o.invitees.len(), changed = ?changes.iter().map(|c| &c.0).collect::<Vec<_>>(), "meeting options");
            let (people, organizer_person) = picker_people(&o, &tenant, &organizer).await;
            json!({
                "options": o.options, "invitees": o.invitees, "people": people,
                "organizer": organizer_person, "tenantId": tenant, "translations": o.translations,
            })
            .to_string()
        }
        Err(e) => {
            tracing::warn!("meeting options: {}", short_error(&e));
            json!({ "options": [], "error": short_error(&e) }).to_string()
        }
    };
    let _ = qt.queue(move |mut this| this.as_mut().set_call_controls_json(QString::from(json.as_str())));
}

/// The names Meeting options' people pickers show ({mri: name}: the
/// invitees, the people picked and the organizer) and the organizer as a
/// picker entry ({mri, objectId, upn, tenantId}), as Teams resolves them
/// through the people service.
async fn picker_people(
    o: &api::meeting_options::MeetingOptions,
    tenant: &str,
    organizer: &str,
) -> (serde_json::Value, serde_json::Value) {
    let organizer_mri = format!("8:orgid:{organizer}");
    let mut mris: Vec<String> = o
        .invitees
        .iter()
        .chain(o.options.iter().flat_map(|op| op["selectedPeople"].as_array().into_iter().flatten()))
        .filter_map(|p| p["mri"].as_str().map(str::to_string))
        .collect();
    mris.push(organizer_mri.clone());
    mris.sort();
    mris.dedup();
    let records = match TeamsClient::new().await {
        Ok(client) => api::directory::short_profile_records(&client, &mris).await.unwrap_or_else(|e| {
            tracing::info!("picker names: {}", short_error(&e));
            Vec::new()
        }),
        Err(_) => Vec::new(),
    };
    let mut names = serde_json::Map::new();
    let mut organizer_person = json!({ "mri": organizer_mri, "objectId": organizer, "tenantId": tenant });
    for r in &records {
        let Some(mri) = r["mri"].as_str() else { continue };
        if let Some(n) = r["displayName"].as_str().filter(|n| !n.is_empty()) {
            names.insert(mri.to_string(), json!(n));
        }
        if mri == organizer_mri {
            organizer_person["upn"] = r["userPrincipalName"].clone();
        }
    }
    (serde_json::Value::Object(names), organizer_person)
}

/// Who was in the call before us (roster updates only carry changes):
/// add the people the updates haven't told us about. The list carries
/// names, not hands or roles.
/// A thread's members with their presence, as JSON for QML.
async fn members_with_presence(thread: &str) -> anyhow::Result<String> {
    let client = TeamsClient::new().await?;
    let members = api::chat_members(&client, thread).await?;
    // Everyone's presence, as Teams' people flyout shows it.
    let mris: Vec<String> = members.iter().map(|m| m.mri.clone()).collect();
    let presence = teams_cli::api::presence::get_presences(&reqwest::Client::new(), &mris)
        .await
        .unwrap_or_default();
    let list: Vec<serde_json::Value> = members
        .iter()
        .map(|m| {
            let mut v = json!(m);
            if let Some(p) = presence.iter().find(|p| p.mri == m.mri) {
                v["presence"] = json!(p.availability);
            }
            v
        })
        .collect();
    Ok(serde_json::to_string(&list).unwrap_or_else(|_| "[]".into()))
}

/// A resumed meeting's people: who's in it now (its join-time roster is
/// stale), then you as it knew you before the hold (your role).
async fn resume_roster(qt: &cxx_qt::CxxQtThread<qobject::Backend>, call: &outgoing::OutgoingCall) {
    let people = call.participants().await.unwrap_or_else(|e| {
        tracing::info!("participants: {}", short_error(&e));
        Vec::new()
    });
    tracing::info!(count = people.len(), "resumed roster");
    let _ = qt.queue(move |mut this| {
        this.as_mut().apply_roster(people);
        let mine = std::mem::take(&mut this.as_mut().rust_mut().held_self);
        this.as_mut().apply_roster(mine);
    });
}

async fn seed_roster(qt: &cxx_qt::CxxQtThread<qobject::Backend>, call: &outgoing::OutgoingCall) {
    // The join response's roster first: it has everyone's streams.
    let joined = call.joined_roster();
    tracing::info!(count = joined.len(), "joined roster");
    let _ = qt.queue(move |mut this| this.as_mut().apply_roster(joined));
    match call.participants().await {
        Ok(people) => {
            tracing::info!(count = people.len(), "call participants");
            let _ = qt.queue(move |mut this| {
                let known: Vec<String> = this.rust().roster.iter().map(|p| p.id.clone()).collect();
                let missing = people
                    .into_iter()
                    .filter(|p| !known.contains(&p.id))
                    .collect();
                this.as_mut().apply_roster(missing)
            });
        }
        Err(e) => tracing::info!("participants: {}", short_error(&e)),
    }
}

/// Where a custom emoji's picture is cached (~/.cache/ost/custom-emoji).
fn custom_emoji_path(document_id: &str) -> Option<std::path::PathBuf> {
    document_id
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || c == '-')
        .then(|| cache_base().join("custom-emoji").join(document_id))
}

fn custom_emoji_cached(document_id: &str) -> Option<std::path::PathBuf> {
    custom_emoji_path(document_id).filter(|p| p.exists())
}

/// A custom emoji's picture, downloaded once into the private cache.
async fn custom_emoji_file(
    client: &TeamsClient,
    document_id: &str,
) -> anyhow::Result<std::path::PathBuf> {
    let path = custom_emoji_path(document_id).context("Bad document id")?;
    if path.exists() {
        return Ok(path);
    }
    let bytes = api::custom_emoji::picture(client, document_id).await?;
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)?;
    }
    std::fs::write(&path, bytes)?;
    Ok(path)
}

/// Teams' emoticon catalogue, loading it if needed.
async fn catalog_loaded() -> Option<std::sync::Arc<api::emoticons::Catalog>> {
    if let Some(c) = emoticon_catalog().read().unwrap().clone() {
        return Some(c);
    }
    match api::emoticons::load_catalog(&cache_base(), "en-us").await {
        Ok(c) => {
            let c = std::sync::Arc::new(c);
            *emoticon_catalog().write().unwrap() = Some(c.clone());
            Some(c)
        }
        Err(e) => {
            tracing::warn!("emoticons unavailable: {}", short_error(&e));
            None
        }
    }
}

/// Fill in the Teams emoticon pictures a message's HTML shows: Teams'
/// Fluent pictures (the 100 px asset for big ones, 50 px in the line).
async fn localize_emoticons(m: &mut api::messages::MessageView) {
    let mut ids = api::messages::emoticon_ids(&m.html);
    for p in &m.flow {
        ids.extend(api::messages::emoticon_ids(&p.html));
    }
    ids.extend(api::messages::emoticon_ids(&m.edit_html));
    ids.sort();
    ids.dedup();
    if ids.is_empty() {
        return;
    }
    let Some(catalog) = catalog_loaded().await else {
        return;
    };
    for id in ids {
        let marker = format!("{}{id}", api::messages::EMOTICON_SRC);
        // Big ones (alone in a message) get the sharper picture.
        let big = m.html.contains(&format!("{marker}\" width=\"50\""));
        let Some(url) = catalog.image_url(&id, if big { 100 } else { 50 }, false) else {
            continue;
        };
        match api::emoticons::image_file(&url, &cache_base()).await {
            Ok(path) => swap_src(m, &marker, &format!("file://{}", path.display())),
            Err(e) => tracing::warn!("emoticon picture failed: {}", short_error(&e)),
        }
    }
}

/// Put a cached file where a message's HTML (and its edit form) has a
/// placeholder src (`from`, a whole src value).
fn swap_src(m: &mut api::messages::MessageView, from: &str, to: &str) {
    let (a, b) = (format!("src=\"{from}\""), format!("src=\"{to}\""));
    let flow = m.flow.iter_mut().map(|p| &mut p.html);
    for html in [&mut m.html, &mut m.edit_html].into_iter().chain(flow) {
        if html.contains(&a) {
            *html = html.replace(&a, &b);
        }
    }
    for e in m.edit_media.iter_mut().filter(|e| e.src == from) {
        e.src = to.to_string();
    }
}

/// An announcement's banner picture, cached like the message's pictures.
async fn localize_banner(client: &TeamsClient, m: &mut api::messages::MessageView) {
    let Some(a) = m.announcement.as_mut() else { return };
    if a.image_url.is_empty() {
        return;
    }
    // The AMS object id from …/objects/{id}/views/….
    let id: String = a
        .image_url
        .split("/objects/")
        .nth(1)
        .and_then(|r| r.split('/').next())
        .unwrap_or_default()
        .chars()
        .filter(|c| c.is_ascii_alphanumeric() || *c == '-' || *c == '_')
        .collect();
    if id.is_empty() {
        return;
    }
    let img = api::messages::InlineImage {
        id,
        url: a.image_url.clone(),
        width: a.image_width,
        height: a.image_height,
        local_path: String::new(),
    };
    match cached_image(client, &img).await {
        Ok(path) => a.image_local = format!("file://{}", path.display()),
        Err(e) => tracing::warn!("banner picture download failed: {}", short_error(&e)),
    }
}

/// The edit form's AMS pictures: their cached files (from `images`).
fn localize_edit_images(m: &mut api::messages::MessageView) {
    let cached: Vec<(String, String)> = m
        .images
        .iter()
        .filter(|i| !i.local_path.is_empty())
        .map(|i| (i.id.clone(), i.local_path.clone()))
        .collect();
    for (id, path) in cached {
        swap_src(m, &format!("{}{id}", api::messages::IMAGE_SRC), &path);
    }
}

/// Fill in the custom emoji pictures a message's HTML shows.
async fn localize_custom_emoji(client: &TeamsClient, m: &mut api::messages::MessageView) {
    let mut docs = api::messages::custom_emoji_docs(&m.html);
    for p in &m.flow {
        docs.extend(api::messages::custom_emoji_docs(&p.html));
    }
    docs.extend(api::messages::custom_emoji_docs(&m.edit_html));
    docs.sort();
    docs.dedup();
    // An edit sends custom emoji again with their picture's address.
    if let Some(base) = client.ams_v2_url() {
        for e in m.edit_media.iter_mut().filter(|e| e.kind == "custom") {
            if let Some(doc) = e.src.strip_prefix(api::messages::CUSTOM_EMOJI_SRC) {
                e.url = api::custom_emoji::picture_url(&base, doc, true);
            }
        }
    }
    for doc in docs {
        match custom_emoji_file(client, &doc).await {
            Ok(path) => swap_src(
                m,
                &format!("{}{doc}", api::messages::CUSTOM_EMOJI_SRC),
                &format!("file://{}", path.display()),
            ),
            Err(e) => tracing::warn!("custom emoji picture failed: {}", short_error(&e)),
        }
    }
}

/// A public picture (an app icon on Teams' CDN) kept in the private image
/// cache, named by its URL's hash.
async fn public_image_file(client: &TeamsClient, url: &str) -> anyhow::Result<std::path::PathBuf> {
    let base = std::env::var_os("XDG_CACHE_HOME")
        .map(std::path::PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| std::path::PathBuf::from(h).join(".cache")))
        .ok_or_else(|| anyhow::anyhow!("No cache directory"))?;
    let dir = base.join("ost").join("images");
    let hash = url.bytes().fold(0xcbf29ce484222325u64, |h, b| (h ^ b as u64).wrapping_mul(0x100000001b3));
    let path = dir.join(format!("app-{hash:016x}"));
    if path.exists() {
        // Pictures cached before SVGs were fixed for Qt.
        if let Ok(old) = std::fs::read(&path)
            && let Some(fixed) = teams_cli::svg::for_qt(&old)
        {
            let _ = std::fs::write(&path, fixed);
        }
        return Ok(path);
    }
    let fetched = client.http().get(url).send().await?.error_for_status()?.bytes().await?;
    let bytes: Vec<u8> = teams_cli::svg::for_qt(&fetched).unwrap_or_else(|| fetched.to_vec());
    std::fs::create_dir_all(&dir)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
        std::fs::set_permissions(base.join("ost"), std::fs::Permissions::from_mode(0o700))?;
        let mut f = std::fs::OpenOptions::new().write(true).create(true).truncate(true).mode(0o600).open(&path)?;
        std::io::Write::write_all(&mut f, &bytes)?;
    }
    #[cfg(not(unix))]
    std::fs::write(&path, &bytes)?;
    Ok(path)
}

/// Keep inline images in a private cache (~/.cache/ost/images, 0700/0600)
/// so they are fetched once.
async fn cached_image(
    client: &TeamsClient,
    img: &api::messages::InlineImage,
) -> anyhow::Result<std::path::PathBuf> {
    let base = std::env::var_os("XDG_CACHE_HOME")
        .map(std::path::PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| std::path::PathBuf::from(h).join(".cache")))
        .ok_or_else(|| anyhow::anyhow!("No cache directory"))?;
    let dir = base.join("ost").join("images");
    let path = dir.join(&img.id);
    if path.exists() {
        return Ok(path);
    }
    let bytes = api::messages::fetch_image(client, &img.url).await?;
    std::fs::create_dir_all(&dir)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
        std::fs::set_permissions(base.join("ost"), std::fs::Permissions::from_mode(0o700))?;
        let mut f = std::fs::OpenOptions::new()
            .write(true)
            .create(true)
            .truncate(true)
            .mode(0o600)
            .open(&path)?;
        std::io::Write::write_all(&mut f, &bytes)?;
    }
    #[cfg(not(unix))]
    std::fs::write(&path, &bytes)?;
    Ok(path)
}

/// Where drafts are kept: $XDG_STATE_HOME/ost/drafts.json (owner-only).
/// Teams keeps drafts on the device too; they are not sent anywhere.
fn drafts_path() -> Option<std::path::PathBuf> {
    std::env::var_os("XDG_STATE_HOME")
        .map(std::path::PathBuf::from)
        .or_else(|| {
            std::env::var_os("HOME").map(|h| std::path::PathBuf::from(h).join(".local/state"))
        })
        .map(|b| b.join("ost").join("drafts.json"))
}

fn load_drafts() -> HashMap<String, (String, u64)> {
    drafts_path()
        .and_then(|p| std::fs::read_to_string(p).ok())
        .and_then(|t| serde_json::from_str(&t).ok())
        .unwrap_or_default()
}

fn save_drafts(drafts: &HashMap<String, (String, u64)>) -> anyhow::Result<()> {
    let path = drafts_path().ok_or_else(|| anyhow::anyhow!("No state directory"))?;
    let dir = path.parent().expect("drafts file has a directory");
    std::fs::create_dir_all(dir)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(dir, std::fs::Permissions::from_mode(0o700))?;
    }
    let tmp = path.with_extension("tmp");
    write_private(&tmp, serde_json::to_string(drafts)?.as_bytes())?;
    std::fs::rename(&tmp, &path)?;
    Ok(())
}

/// App settings (theme and the like): $XDG_CONFIG_HOME/ost/desktop.json,
/// owner-only. Teams keeps these per user; OST keeps them per device.
fn settings_path() -> Option<std::path::PathBuf> {
    std::env::var_os("XDG_CONFIG_HOME")
        .map(std::path::PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| std::path::PathBuf::from(h).join(".config")))
        .map(|b| b.join("ost").join("desktop.json"))
}

fn load_settings() -> serde_json::Map<String, serde_json::Value> {
    settings_path()
        .and_then(|p| std::fs::read_to_string(p).ok())
        .and_then(|t| serde_json::from_str(&t).ok())
        .unwrap_or_default()
}

fn save_settings(map: &serde_json::Map<String, serde_json::Value>) -> anyhow::Result<()> {
    let path = settings_path().ok_or_else(|| anyhow::anyhow!("No config directory"))?;
    let dir = path.parent().expect("settings file has a directory");
    std::fs::create_dir_all(dir)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(dir, std::fs::Permissions::from_mode(0o700))?;
    }
    let tmp = path.with_extension("tmp");
    write_private(&tmp, serde_json::to_string_pretty(map)?.as_bytes())?;
    std::fs::rename(&tmp, &path)?;
    Ok(())
}

/// Hand the chosen microphone and speaker to the call engine.
fn apply_audio_devices(map: &serde_json::Map<String, serde_json::Value>) {
    let get = |k: &str| {
        map.get(k)
            .and_then(|v| v.as_str())
            .filter(|v| !v.is_empty() && *v != "default")
            .map(str::to_string)
    };
    teams_cli::calling::audio::set_preferred_devices(get("micDevice"), get("speakerDevice"));
    // Teams' Noise suppression switch (on unless turned off).
    teams_cli::calling::apm::set_noise_level(
        if map.get("noiseSuppression").and_then(|v| v.as_str()) == Some("off") {
            teams_cli::calling::apm::NoiseLevel::Off
        } else {
            teams_cli::calling::apm::NoiseLevel::High
        },
    );
    // Teams' High fidelity music mode and its echo cancellation choice.
    let flag = |k: &str, default: bool| match map.get(k).and_then(|v| v.as_str()) {
        Some("on") => true,
        Some("off") => false,
        _ => default,
    };
    teams_cli::calling::apm::set_music_mode(flag("musicMode", false), flag("musicModeEcho", true));
}

/// Start OST when you sign in to the desktop (an XDG autostart entry).
fn set_autostart(on: bool) -> anyhow::Result<()> {
    let dir = std::env::var_os("XDG_CONFIG_HOME")
        .map(std::path::PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| std::path::PathBuf::from(h).join(".config")))
        .ok_or_else(|| anyhow::anyhow!("No config directory"))?
        .join("autostart");
    let file = dir.join("ost-desktop.desktop");
    if !on {
        match std::fs::remove_file(&file) {
            Err(e) if e.kind() != std::io::ErrorKind::NotFound => return Err(e.into()),
            _ => return Ok(()),
        }
    }
    let exe = std::env::current_exe()?;
    std::fs::create_dir_all(&dir)?;
    let entry = format!(
        "[Desktop Entry]\nType=Application\nName=OST\nComment=Teams client\nExec=\"{}\"\nIcon=ost\nTerminal=false\nX-GNOME-Autostart-enabled=true\n",
        exe.display()
    );
    std::fs::write(&file, entry)?;
    Ok(())
}

/// How many notifications the Activity feed shows.
const ACTIVITY_LIMIT: usize = 50;

/// How long a downloaded picture (or "has none") is trusted before it is
/// fetched again.
const PHOTO_TTL: std::time::Duration = std::time::Duration::from_secs(24 * 3600);

/// Where pictures are cached: ~/.cache/ost/photos (owner-only).
fn photo_dir() -> Option<std::path::PathBuf> {
    std::env::var_os("XDG_CACHE_HOME")
        .map(std::path::PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| std::path::PathBuf::from(h).join(".cache")))
        .map(|b| b.join("ost").join("photos"))
}

/// Note a team picture's ETag; true when it differs from the one noted
/// before (or none was, while a picture is cached), so the cached picture
/// is stale.
fn team_picture_changed(group: &str, etag: &str) -> bool {
    let (Some(dir), false) = (photo_dir(), etag.is_empty()) else {
        return false;
    };
    let oid = group.to_ascii_lowercase();
    if oid.len() != 36 || !oid.chars().all(|c| c.is_ascii_hexdigit() || c == '-') {
        return false;
    }
    let file = dir.join(format!("team-{oid}.etag"));
    let before = std::fs::read_to_string(&file).ok();
    if before.as_deref() == Some(etag) {
        return false;
    }
    let _ = std::fs::create_dir_all(&dir);
    let _ = std::fs::write(&file, etag);
    match before {
        Some(_) => true,
        // First sight: stale only if a picture is already cached.
        None => std::fs::read_dir(&dir)
            .map(|d| d.flatten().any(|e| {
                let n = e.file_name().to_string_lossy().to_string();
                n.starts_with(&format!("team-{oid}-")) && !n.ends_with(".etag")
            }))
            .unwrap_or(false),
    }
}

/// The owner and object id behind a photo_for id.
fn photo_target(id: &str, my_oid: Option<&str>) -> Option<(api::directory::PhotoOwner, String)> {
    use api::directory::PhotoOwner;
    // A meeting guest has no directory id: Teams draws them by name.
    if id.starts_with("8:teamsvisitor:") {
        return Some((PhotoOwner::Named, String::new()));
    }
    let (owner, oid) = if id == "me" {
        (PhotoOwner::User, my_oid?.to_string())
    } else if let Some(g) = id.strip_prefix("team:") {
        (PhotoOwner::Team, g.to_string())
    } else {
        (
            PhotoOwner::User,
            id.strip_prefix("8:orgid:").unwrap_or(id).to_string(),
        )
    };
    let valid = oid.len() == 36 && oid.chars().all(|c| c.is_ascii_hexdigit() || c == '-');
    valid.then_some((owner, oid.to_ascii_lowercase()))
}

/// A cached picture: Some(Some(url)) when there is one, Some(None) when
/// the account has none; `fresh` says whether it is within PHOTO_TTL.
fn photo_from_disk(key: &str) -> (Option<Option<String>>, bool) {
    let Some(dir) = photo_dir() else {
        return (None, false);
    };
    let fresh = |p: &std::path::Path| {
        p.metadata()
            .and_then(|m| m.modified())
            .ok()
            .and_then(|t| t.elapsed().ok())
            .is_some_and(|age| age < PHOTO_TTL)
    };
    let jpg = dir.join(format!("{key}.jpg"));
    if jpg.exists() {
        return (Some(Some(format!("file://{}", jpg.display()))), fresh(&jpg));
    }
    let none = dir.join(format!("{key}.none"));
    if none.exists() {
        return (Some(None), fresh(&none));
    }
    (None, false)
}

/// Download a picture into the cache; returns its file URL, or None when
/// the account has no picture.
async fn fetch_photo(
    owner: api::directory::PhotoOwner,
    oid: &str,
    name: &str,
    key: &str,
) -> anyhow::Result<Option<String>> {
    let client = TeamsClient::new().await?;
    let bytes = api::directory::photo(&client, owner, oid, name).await?;
    let dir = photo_dir().ok_or_else(|| anyhow::anyhow!("No cache directory"))?;
    std::fs::create_dir_all(&dir)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        if let Some(ost) = dir.parent() {
            std::fs::set_permissions(ost, std::fs::Permissions::from_mode(0o700))?;
        }
        std::fs::set_permissions(&dir, std::fs::Permissions::from_mode(0o700))?;
    }
    let jpg = dir.join(format!("{key}.jpg"));
    let none = dir.join(format!("{key}.none"));
    match bytes {
        Some(b) => {
            let tmp = dir.join(format!("{key}.tmp"));
            write_private(&tmp, &b)?;
            std::fs::rename(&tmp, &jpg)?;
            let _ = std::fs::remove_file(&none);
            Ok(Some(format!("file://{}", jpg.display())))
        }
        None => {
            write_private(&none, b"")?;
            let _ = std::fs::remove_file(&jpg);
            Ok(None)
        }
    }
}

/// Write a file readable only by its owner.
fn write_private(path: &std::path::Path, bytes: &[u8]) -> std::io::Result<()> {
    let mut opts = std::fs::OpenOptions::new();
    opts.write(true).create(true).truncate(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        opts.mode(0o600);
    }
    std::io::Write::write_all(&mut opts.open(path)?, bytes)
}

impl qobject::Backend {
    pub fn start(mut self: Pin<&mut Self>) {
        let _ = QT_THREAD.set(self.qt_thread());
        // The machine's lock state feeds presence, as Teams' host does.
        runtime().spawn(crate::lock_watch::run());
        let frame = std::env::var_os("OST_SYSTEM_FRAME").is_some_and(|v| v != "0");
        self.as_mut().set_system_frame(frame);
        // Teams' default theme is "Follow operating system theme".
        let theme = load_settings()
            .get("theme")
            .and_then(|t| t.as_str())
            .filter(|t| ["system", "light", "dark"].contains(t))
            .unwrap_or("system")
            .to_string();
        self.as_mut().set_theme_mode(QString::from(theme.as_str()));
        apply_audio_devices(&load_settings());
        self.as_mut().publish_drafts();
        let stored = teams_cli::auth::has_credentials();
        self.as_mut().set_has_credentials(stored);
        if stored {
            self.refresh();
        }
    }

    pub fn begin_sign_in(mut self: Pin<&mut Self>) {
        self.as_mut().set_busy(true);
        self.as_mut().set_status_text(QString::default());
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let pending = match teams_cli::auth::begin_sign_in().await {
                Ok(p) => p,
                Err(e) => {
                    let msg = short_error(&e);
                    let _ = qt.queue(move |mut this| {
                        this.as_mut().set_busy(false);
                        this.as_mut().set_status_text(QString::from(msg.as_str()));
                    });
                    return;
                }
            };
            let code = pending.user_code().to_string();
            let url = pending.verification_uri().to_string();
            let _ = qt.queue(move |mut this| {
                this.as_mut().set_sign_in_code(QString::from(code.as_str()));
                this.as_mut().set_sign_in_url(QString::from(url.as_str()));
            });
            let result = teams_cli::auth::finish_sign_in(pending).await;
            let _ = qt.queue(move |mut this| {
                this.as_mut().set_busy(false);
                this.as_mut().set_sign_in_code(QString::default());
                this.as_mut().set_sign_in_url(QString::default());
                match result {
                    Ok(missing) => {
                        if !missing.is_empty() {
                            tracing::warn!("signed in without: {}", missing.join(", "));
                        }
                        this.as_mut().set_has_credentials(true);
                        this.as_mut().refresh();
                    }
                    Err(e) => this
                        .as_mut()
                        .set_status_text(QString::from(short_error(&e).as_str())),
                }
            });
        });
    }

    pub fn sign_out(mut self: Pin<&mut Self>) {
        // As Teams: remove this presence endpoint before the tokens go
        // (the request needs them).
        let _ = runtime().block_on(async {
            tokio::time::timeout(
                std::time::Duration::from_secs(5),
                teams_cli::api::presence::delete_endpoint(&reqwest::Client::new()),
            )
            .await
        });
        if let Err(e) = teams_cli::auth::sign_out() {
            self.as_mut()
                .set_status_text(QString::from(short_error(&e).as_str()));
            return;
        }
        self.as_mut().set_has_credentials(false);
        self.as_mut().set_signed_in(false);
        self.as_mut().set_user_name(QString::default());
        self.as_mut().set_chats_json(QString::from("[]"));
        self.as_mut().set_messages_json(QString::from("[]"));
        self.as_mut().set_current_chat_id(QString::default());
        self.as_mut().set_current_chat_name(QString::default());
        self.as_mut().rust_mut().unread.clear();
        self.as_mut().rust_mut().chats.clear();
    }

    /// Hand the chat list, with unread flags, to QML.
    fn publish_chats(mut self: Pin<&mut Self>) {
        let unread = &self.rust().unread;
        let list: Vec<_> = self
            .rust()
            .chats
            .iter()
            .map(|c| {
                let mut c = c.clone();
                let id = c["id"].as_str().unwrap_or_default().to_string();
                c["unread"] = json!(unread.contains(&id));
                if let Some(mri) = c["peerMri"].as_str()
                    && let Some(p) = self.rust().presence.get(mri)
                {
                    c["presence"] = json!(p);
                }
                if let Some(mri) = c["peerMri"].as_str()
                    && let Some(n) = self.rust().peer_notes.get(mri)
                {
                    c["peerNote"] = n.clone();
                }
                c
            })
            .collect();
        let text = serde_json::to_string(&list).unwrap_or_else(|_| "[]".into());
        self.as_mut().set_chats_json(QString::from(text.as_str()));
        // Draft names come from the chat list.
        self.as_mut().publish_drafts();
    }

    /// Connect to Trouter once per process and react to pushed chat events:
    /// reload the open chat, mark others unread, and refresh the list order.
    fn start_push(mut self: Pin<&mut Self>) {
        static STARTED: AtomicBool = AtomicBool::new(false);
        if STARTED.swap(true, Ordering::SeqCst) {
            return;
        }
        let mut events = teams_cli::event_hub::subscribe();
        self.as_mut().load_recent_reactions();
        // The outbox: redraw the open chat whenever a send changes state, and
        // replay queued sends at startup and every 10 minutes (Teams'
        // OfflineActionsSyncStrategy); Trouter connects replay too (below).
        {
            let qt = self.qt_thread();
            let mut changes = outbox().changes();
            runtime().spawn(async move {
                while changes.changed().await.is_ok() {
                    let _ = qt.queue(|mut this| this.as_mut().refresh_lies());
                }
            });
            runtime().spawn(async {
                loop {
                    outbox().replay();
                    tokio::time::sleep(api::outbox::REPLAY_INTERVAL).await;
                }
            });
        }
        runtime().spawn(async {
            let opts = teams_cli::trouter::ListenOptions::EMBEDDED;
            if let Err(e) = teams_cli::trouter::listen(opts, std::future::pending).await {
                tracing::warn!("push channel stopped: {}", short_error(&e));
            }
        });
        let qt = self.qt_thread();
        runtime().spawn(async move {
            use teams_cli::event_hub::EventKind;
            use tokio::sync::broadcast::error::RecvError;
            loop {
                let ev = match events.recv().await {
                    Ok(ev) => ev,
                    Err(RecvError::Lagged(n)) => {
                        tracing::warn!("missed {n} push events; reloading");
                        let _ = qt.queue(|mut this| {
                            this.as_mut().reload_messages();
                            this.as_mut().reload_chats();
                        });
                        continue;
                    }
                    Err(RecvError::Closed) => return,
                };
                if ev.kind == EventKind::Connected {
                    // Teams replays its offline queue when Trouter connects.
                    outbox().replay();
                    continue;
                }
                if ev.kind == EventKind::Call {
                    on_call_event(&qt, &ev.json).await;
                    continue;
                }
                for m in teams_cli::event_hub::message_events(&ev.json) {
                    let qt2 = qt.clone();
                    let _ = qt.queue(move |mut this| {
                        this.as_mut().typer_posted(&m);
                        this.as_mut().maybe_chat_bubble(&m);
                        this.as_mut().maybe_notify(m, qt2)
                    });
                }
                for t in teams_cli::event_hub::typing_events(&ev.json) {
                    let _ = qt.queue(move |mut this| this.as_mut().on_typing(t));
                }
                let ids = teams_cli::event_hub::conversation_ids(&ev.json);
                if ids.is_empty() {
                    continue;
                }
                tracing::info!(chats = ids.len(), "chat push");
                let _ = qt.queue(move |mut this| this.as_mut().on_chat_push(ids));
            }
        });
    }

    pub fn accept_call(mut self: Pin<&mut Self>, with_video: bool) {
        if self.rust().call_state.to_string() != "ringing" {
            return;
        }
        self.as_mut().set_call_state(QString::from("connecting"));
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let Some(call) = call_slot().lock().await.ringing.take() else {
                return;
            };
            let result = async {
                let auth = CallAuth::load().await?;
                auth.answer(call, with_video, true).await
            }
            .await;
            match result {
                Ok(mut active) => {
                    let has_audio = active.has_audio();
                    let can_video = active.can_send_video();
                    let can_dtmf = active.can_dtmf();
                    // Accept with video: the camera starts on.
                    let camera = with_video
                        && can_video
                        && match active.set_camera(true, camera_device()) {
                            Ok(()) => true,
                            Err(e) => {
                                tracing::info!("camera: {}", short_error(&e));
                                false
                            }
                        };
                    let can_share = active.can_share();
                    tracing::info!(has_audio, can_video, camera, can_share, "call answered");
                    call_slot().lock().await.active = Some(active);
                    spawn_call_stats_logger(qt.clone());
                    let _ = qt.queue(move |mut this| {
                        this.as_mut().set_call_has_audio(has_audio);
                        this.as_mut().set_call_can_video(can_video);
                        this.as_mut().set_call_can_dtmf(can_dtmf);
                        this.as_mut().set_call_can_share(can_share);
                        this.as_mut().set_call_camera_on(camera);
                        this.as_mut().set_call_muted(false);
                        this.as_mut().set_call_state(QString::from("connected"));
                    });
                }
                Err(e) => {
                    let msg = short_error(&e);
                    tracing::warn!("answer failed: {msg}");
                    let _ = qt.queue(move |mut this| {
                        this.as_mut().set_status_text(QString::from(msg.as_str()));
                        this.as_mut().end_call_ui();
                    });
                }
            }
        });
    }

    pub fn decline_call(mut self: Pin<&mut Self>) {
        self.as_mut().end_call_ui();
        runtime().spawn(async {
            let Some(call) = call_slot().lock().await.ringing.take() else {
                return;
            };
            let result = async { CallAuth::load().await?.decline(&call).await }.await;
            if let Err(e) = result {
                tracing::warn!("decline failed: {}", short_error(&e));
            }
        });
    }

    pub fn start_call(self: Pin<&mut Self>) {
        self.start_call_with(false);
    }

    pub fn start_video_call(self: Pin<&mut Self>) {
        self.start_call_with(true);
    }

    /// Remember the 1:1 header's call choice when it changes, as Teams does
    /// (944031: only with a new choice).
    fn remember_header_call(mut self: Pin<&mut Self>, video: bool) {
        if self.rust().header_call_video == video {
            return;
        }
        self.as_mut().set_header_call_video(video);
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                api::preferences::update_personal_settings(
                    &client,
                    &api::preferences::header_call_patch(video),
                )
                .await
            }
            .await;
            if let Err(e) = result {
                tracing::warn!("call choice not saved: {}", short_error(&e));
            }
        });
    }

    fn start_call_with(mut self: Pin<&mut Self>, video: bool) {
        if !self.rust().call_state.is_empty() {
            return;
        }
        let chat_id = self.rust().current_chat_id.to_string();
        let peer = self.rust().current_chat_name.clone();
        let my_oid = teams_cli::config::Config::load()
            .ok()
            .and_then(|c| c.object_id())
            .unwrap_or_default();
        tracing::info!(chat = %chat_id, has_oid = !my_oid.is_empty(), "start call");
        // In a group chat this is the chevron's Audio call: members are rung.
        if outgoing::is_group_chat(&chat_id) {
            self.start_group_call(
                chat_id,
                peer,
                Some(teams_cli::calling::signaling::GroupCallKind::Ring),
            );
            return;
        }
        let Some(callee) = outgoing::callee_mri_for_chat(&chat_id, &my_oid) else {
            self.as_mut()
                .set_status_text(QString::from("Calls are available in 1:1 chats"));
            return;
        };
        self.as_mut().remember_header_call(video);
        self.as_mut().set_call_peer(peer);
        self.as_mut()
            .set_call_peer_id(QString::from(callee.as_str()));
        self.as_mut().set_call_video_offered(false);
        self.as_mut().set_call_meeting(false);
        self.as_mut().set_call_scheduled(false);
        self.as_mut().set_call_ai_indicator(false);
        self.as_mut().show_processing(Default::default());
        self.as_mut().show_transcript(Vec::new(), true);
        self.as_mut().reset_captions();
        self.as_mut().set_call_muted(false);
        self.as_mut().set_call_state(QString::from("calling"));
        let qt = self.qt_thread();
        let (cancel_tx, cancel_rx) = tokio::sync::oneshot::channel();
        runtime().block_on(async { call_slot().lock().await.cancel_placing = Some(cancel_tx) });
        runtime().spawn(async move {
            let result = outgoing::place_call(&chat_id, &callee, video, cancel_rx).await;
            let mut slot = call_slot().lock().await;
            slot.cancel_placing = None;
            match result {
                Ok(mut call) => {
                    let has_audio = call.has_audio();
                    let can_dtmf = call.can_dtmf();
                    let can_video = call.can_send_video();
                    let can_share = call.can_share();
                    // A video call starts with the camera on.
                    let camera = video
                        && can_video
                        && match call.set_camera(true, camera_device()) {
                            Ok(()) => true,
                            Err(e) => {
                                tracing::info!("camera: {}", short_error(&e));
                                false
                            }
                        };
                    tracing::info!(
                        has_audio,
                        can_dtmf,
                        can_video,
                        can_share,
                        camera,
                        "outgoing call connected"
                    );
                    slot.outgoing = Some(call);
                    drop(slot);
                    spawn_call_stats_logger(qt.clone());
                    let _ = qt.queue(move |mut this| {
                        this.as_mut().set_call_has_audio(has_audio);
                        this.as_mut().set_call_can_dtmf(can_dtmf);
                        this.as_mut().set_call_can_video(can_video);
                        this.as_mut().set_call_can_share(can_share);
                        this.as_mut().set_call_camera_on(camera);
                        this.as_mut().set_call_state(QString::from("connected"));
                    });
                }
                Err(e) => {
                    drop(slot);
                    let msg = short_error(&e);
                    tracing::info!("outgoing call ended: {msg}");
                    let _ = qt.queue(move |mut this| {
                        this.as_mut().set_status_text(QString::from(msg.as_str()));
                        this.as_mut().end_call_ui();
                    });
                }
            }
        });
    }

    pub fn channel_meet_now(self: Pin<&mut Self>, channel_id: &QString, title: &QString) {
        let channel = channel_id.to_string();
        if !self.rust().call_state.is_empty() || !channel.ends_with("@thread.tacv2") {
            return;
        }
        self.start_group_call(channel, title.clone(), None);
    }

    pub fn meet_now(self: Pin<&mut Self>) {
        let chat_id = self.rust().current_chat_id.to_string();
        let title = self.rust().current_chat_name.clone();
        if !self.rust().call_state.is_empty() || !outgoing::is_group_chat(&chat_id) {
            return;
        }
        self.start_group_call(
            chat_id,
            title,
            Some(teams_cli::calling::signaling::GroupCallKind::Huddle),
        );
    }

    pub fn watch_chat_call(
        self: Pin<&mut Self>,
        thread_id: &QString,
        conversation_url: &QString,
        call_id: &QString,
    ) {
        let (thread, url, id) = (
            thread_id.to_string(),
            conversation_url.to_string(),
            call_id.to_string(),
        );
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let mut w = watched_call().lock().await;
            if w.as_ref().is_some_and(|x| x.thread_id == thread) {
                return;
            }
            if let Some(old) = w.take() {
                old.leave().await;
            }
            let json = if thread.is_empty() || url.is_empty() {
                "[]".to_string()
            } else {
                match teams_cli::calling::live_roster::LiveRoster::subscribe(&thread, &url, &id)
                    .await
                {
                    Ok(sub) => {
                        let json = live_roster_json(&sub);
                        tracing::info!(people = sub.roster.len(), "watching the chat's call");
                        *w = Some(sub);
                        json
                    }
                    Err(e) => {
                        tracing::warn!("live roster: {}", short_error(&e));
                        "[]".to_string()
                    }
                }
            };
            let _ = qt.queue(move |mut this| {
                this.as_mut()
                    .set_chat_live_roster_json(QString::from(json.as_str()))
            });
        });
    }

    pub fn join_group_call(self: Pin<&mut Self>) {
        let chat_id = self.rust().current_chat_id.to_string();
        let title = self.rust().current_chat_name.clone();
        if !self.rust().call_state.is_empty() || !outgoing::is_group_chat(&chat_id) {
            return;
        }
        self.start_group_call(
            chat_id,
            title,
            Some(teams_cli::calling::signaling::GroupCallKind::Join),
        );
    }

    /// A group chat's call (Meet now, Audio call or Join), shown with the
    /// meeting window.
    fn start_group_call(
        mut self: Pin<&mut Self>,
        chat_id: String,
        title: QString,
        // None: a new meeting in a channel, titled `title` (Meet now).
        kind: Option<teams_cli::calling::signaling::GroupCallKind>,
    ) {
        let subject = title.to_string();
        self.as_mut().set_call_peer(title);
        self.as_mut().set_call_peer_id(QString::default());
        self.as_mut().rust_mut().roster.clear();
        self.as_mut().set_call_roster_json(QString::from("[]"));
        self.as_mut().set_call_video_json(QString::from("{}"));
        self.as_mut().set_call_speaker_mri(QString::default());
        self.as_mut().set_call_speaking_json(QString::from("[]"));
        self.as_mut().set_call_muted_by_meeting(false);
        self.as_mut().set_call_share_mri(QString::default());
        self.as_mut().set_call_lobby_json(QString::from("[]"));
        self.as_mut().set_call_invite_url(QString::default());
        self.as_mut()
            .set_call_thread_id(QString::from(chat_id.as_str()));
        self.as_mut().load_call_chat_members();
        self.as_mut().set_call_scheduled(false);
        self.as_mut().set_call_ai_indicator(false);
        self.as_mut().show_processing(Default::default());
        self.as_mut().show_transcript(Vec::new(), true);
        self.as_mut().reset_captions();
        self.as_mut().set_call_meeting(true);
        self.as_mut().set_call_video_offered(false);
        self.as_mut().set_call_muted(false);
        self.as_mut().set_call_state(QString::from("connecting"));
        let qt = self.qt_thread();
        let (cancel_tx, cancel_rx) = tokio::sync::oneshot::channel();
        runtime().block_on(async { call_slot().lock().await.cancel_placing = Some(cancel_tx) });
        runtime().spawn(async move {
            let result = match kind {
                Some(kind) => outgoing::start_group_call(&chat_id, kind, cancel_rx).await,
                None => outgoing::start_channel_meeting(&chat_id, &subject, cancel_rx).await,
            };
            let mut slot = call_slot().lock().await;
            slot.cancel_placing = None;
            match result {
                Ok(call) => {
                    let has_audio = call.has_audio();
                    let can_dtmf = call.can_dtmf();
                    let can_video = call.can_send_video();
                    let can_share = call.can_share();
                    tracing::info!(has_audio, can_dtmf, can_video, can_share, "group call started");
                    seed_roster(&qt, &call).await;
                    slot.outgoing = Some(call);
                    drop(slot);
                    spawn_call_stats_logger(qt.clone());
                    let _ = qt.queue(move |mut this| {
                        this.as_mut().set_call_has_audio(has_audio);
                        this.as_mut().set_call_can_dtmf(can_dtmf);
                        this.as_mut().set_call_can_video(can_video);
                        this.as_mut().set_call_can_share(can_share);
                        this.as_mut().set_call_state(QString::from("connected"));
                    });
                }
                Err(e) => {
                    drop(slot);
                    let msg = short_error(&e);
                    tracing::info!("group call ended: {msg}");
                    let _ = qt.queue(move |mut this| {
                        this.as_mut().set_status_text(QString::from(
                            format!("Couldn't start the call: {msg}").as_str(),
                        ));
                        this.as_mut().end_call_ui();
                    });
                }
            }
        });
    }

    /// The meeting the call is in, as its join link names it.
    fn call_meeting_link(&self) -> Option<outgoing::MeetingLink> {
        outgoing::MeetingLink::parse(&self.rust().last_join.0.to_string())
            .filter(|l| l.tenant_id.is_some() && l.organizer_id.is_some())
    }

    pub fn share_action(self: Pin<&mut Self>, op: &QString, item_json: &QString, args_json: &QString) {
        let op = op.to_string();
        let item: api::sharing::ItemRef = serde_json::from_str(&item_json.to_string()).unwrap_or_default();
        let args: serde_json::Value = serde_json::from_str(&args_json.to_string()).unwrap_or(json!({}));
        let group_chats = group_chat_ids(&self.rust().chats_json.to_string());
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let s = |k: &str| args[k].as_str().unwrap_or_default().to_string();
            let result: anyhow::Result<serde_json::Value> = async {
                // "sf:<op>" / "fw:<op>": the same op for Share this file and
                // Forward (each dialog takes only its own replies).
                Ok(match op.rsplit(':').next().unwrap_or_default() {
                    "info" => {
                        let mut info = api::sharing::info(&item).await?;
                        if let Ok(client) = TeamsClient::new().await {
                            api::sharing::with_object_ids(&client, &mut info).await;
                        }
                        json!(info)
                    }
                    "people" => json!({ "query": s("query"), "people": api::sharing::search_people(&item.site, &s("query")).await? }),
                    "send" => {
                        let people = args["people"].as_array().cloned().unwrap_or_default();
                        api::sharing::send(&item, &people, args["edit"].as_bool().unwrap_or(true), &s("message")).await?;
                        json!(null)
                    }
                    "link" | "copy" => {
                        let (url, share_id) = api::sharing::create_link(&item, args["scope"].as_i64().unwrap_or(1), args["edit"].as_bool().unwrap_or(false), &s("expiration"), &s("password")).await?;
                        json!({ "url": url, "share_id": share_id })
                    }
                    "recipients" => {
                        let oid = TeamsClient::new().await.ok().and_then(|c| c.object_id()).unwrap_or_default();
                        json!({ "query": s("query"), "items": api::search::recipients(&s("query"), &oid).await? })
                    }
                    "access" => {
                        let upns: Vec<String> = args["upns"].as_array().into_iter().flatten().filter_map(|u| u.as_str().map(str::to_string)).collect();
                        json!(api::sharing::check_access(&item, &upns).await?.into_iter().map(|(u, ok)| json!({ "upn": u, "ok": ok })).collect::<Vec<_>>())
                    }
                    "post" => {
                        let client = TeamsClient::new().await?;
                        let targets = args["targets"].as_array().cloned().unwrap_or_default();
                        let chat = picked_conversation(&client, &targets, &group_chats).await?;
                        let f = &args["file"];
                        let fs = |k: &str| f[k].as_str().unwrap_or_default().to_string();
                        let record = api::files::shared_record(&fs("name"), &item.item, &fs("object_url"), &item.site, &fs("share_url"), &fs("share_id"));
                        // The note as the share dialog's editor wrote it (Format), else plain.
                        let note_html = s("note_html");
                        if note_html.trim().is_empty() {
                            api::files::send_with_files(&client, &chat, &s("note"), vec![record]).await?;
                        } else {
                            let (html, _) = api::messages::teams_html_with_media(&note_html, &[]);
                            api::files::send_html_with_files(&client, &chat, &html, vec![record]).await?;
                        }
                        json!({ "chat": chat })
                    }
                    "role" => {
                        api::sharing::set_role(&item, &s("login"), args["role"].as_i64().unwrap_or(0)).await?;
                        json!(null)
                    }
                    "stop" => {
                        api::sharing::stop_sharing(&item).await?;
                        json!(null)
                    }
                    "unlink" => {
                        api::sharing::delete_link(&item, args["kind"].as_i64().unwrap_or_default(), &s("share_id")).await?;
                        json!(null)
                    }
                    other => anyhow::bail!("unknown share action {other}"),
                })
            }
            .await;
            let (value, error) = match result {
                Ok(v) => (v.to_string(), String::new()),
                Err(e) => {
                    tracing::warn!("share {op}: {}", short_error(&e));
                    (String::new(), short_error(&e))
                }
            };
            let _ = qt.queue(move |mut this| this.as_mut().share_done(QString::from(op.as_str()), QString::from(value.as_str()), QString::from(error.as_str())));
        });
    }

    pub fn breakout_action(self: Pin<&mut Self>, action: &QString, args_json: &QString) {
        let action = action.to_string();
        let args: serde_json::Value = serde_json::from_str(&args_json.to_string()).unwrap_or(json!({}));
        // From a room joined over the held main meeting, the main meeting.
        let held: serde_json::Value = serde_json::from_str(&self.rust().call_held_meeting_json.to_string()).unwrap_or_default();
        let link = held["url"]
            .as_str()
            .and_then(outgoing::MeetingLink::parse)
            .filter(|l| l.tenant_id.is_some() && l.organizer_id.is_some())
            .or_else(|| self.call_meeting_link());
        let Some(link) = link else {
            tracing::warn!("breakout rooms: no meeting");
            return;
        };
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = breakout_run(&action, &args, &link).await;
            let error = match &result {
                Ok(state) => {
                    let text = state.to_string();
                    let _ = qt.queue(move |mut this| this.as_mut().set_call_breakout_rooms_json(QString::from(text.as_str())));
                    String::new()
                }
                Err(e) => {
                    tracing::warn!("breakout rooms {action}: {}", short_error(e));
                    short_error(e)
                }
            };
            tracing::info!(action, ok = error.is_empty(), "breakout rooms action");
            let _ = qt.queue(move |this| this.breakout_action_done(QString::from(action.as_str()), QString::from(error.as_str())));
        });
    }

    pub fn join_room_holding_main(mut self: Pin<&mut Self>, join_url: &QString, title: &QString) {
        let (url, title) = (join_url.to_string(), title.to_string());
        let (main_url, main_title) = self.rust().last_join.clone();
        let me = self.rust().user_mri.to_string().to_ascii_lowercase();
        let mine: Vec<_> = self.rust().roster.iter().filter(|p| p.id == me).cloned().collect();
        self.as_mut().rust_mut().held_self = mine;
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let mut slot = call_slot().lock().await;
            let Some(call) = slot.outgoing.take() else { return };
            // Teams holds the organizer's main meeting while they're in a
            // room (its window shows "On hold" and Resume): a local hold
            // (CallState.LocalHold) — the meeting stays joined, nothing is
            // sent or played. The service's hold is for 1:1 calls (a
            // meeting answers its resume with 430 "Unable to find a
            // holdee").
            call.set_held(true);
            tracing::info!("main meeting on hold for a breakout room");
            slot.held_main = Some((call, main_url.clone(), main_title.clone()));
            drop(slot);
            let thread = outgoing::MeetingLink::parse(&main_url.to_string()).map(|l| l.thread_id).unwrap_or_default();
            let held = json!({
                "title": main_title.to_string(), "url": main_url.to_string(), "thread": thread,
                "since": std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_millis() as u64).unwrap_or(0),
            })
            .to_string();
            let _ = qt.queue(move |mut this| {
                this.as_mut().set_call_held_meeting_json(QString::from(held.as_str()));
                this.as_mut().set_call_camera_on(false);
                this.as_mut().set_call_state(QString::default());
                this.as_mut().join_meeting(&QString::from(url.as_str()), &QString::from(title.as_str()));
            });
        });
    }

    pub fn leave_held_meeting(mut self: Pin<&mut Self>) {
        self.as_mut().set_call_held_meeting_json(QString::default());
        runtime().spawn(async {
            let held = call_slot().lock().await.held_main.take();
            if let Some((main, _, _)) = held {
                leave_moved_from(main).await;
            }
        });
    }

    pub fn leave_room(self: Pin<&mut Self>, resume: bool) {
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let mut slot = call_slot().lock().await;
            let room = slot.outgoing.take();
            let held = slot.held_main.take();
            drop(slot);
            if let Some(room) = room {
                // The room's own end is that call's, not the main meeting's.
                let tag = room.call_tag().to_string();
                call_slot().lock().await.left_tags.push(tag);
                if let Err(e) = room.hang_up().await {
                    tracing::warn!("leaving the room: {}", short_error(&e));
                }
            }
            let Some((main, url, title)) = held else {
                let _ = qt.queue(|mut this| this.as_mut().end_call_ui());
                return;
            };
            if !resume {
                if let Err(e) = main.hang_up().await {
                    tracing::warn!("leaving the meeting: {}", short_error(&e));
                }
                let _ = qt.queue(|mut this| {
                    this.as_mut().set_call_held_meeting_json(QString::default());
                    this.as_mut().end_call_ui();
                });
                return;
            }
            main.set_held(false);
            tracing::info!("back in the main meeting");
            let view = JoinedView::of(&main);
            // The window becomes the main meeting's again, then its people
            // and state (queued in that order).
            let _ = qt.queue(move |mut this| {
                if let Some(link) = outgoing::MeetingLink::parse(&url.to_string()) {
                    this.as_mut().reset_meeting_view(&link, &url, &title);
                }
                this.as_mut().set_call_held_meeting_json(QString::default());
                this.as_mut().set_call_breakout_json(QString::default());
                this.as_mut().set_call_breakout_room_json(QString::default());
                // Through "connecting" back to "connected", as a join goes
                // (the window takes up the meeting's own time again).
                this.as_mut().set_call_state(QString::from("connecting"));
            });
            resume_roster(&qt, &main).await;
            call_slot().lock().await.outgoing = Some(main);
            let _ = qt.queue(move |mut this| this.as_mut().show_joined(view, false));
        });
    }

    pub fn current_meeting(self: Pin<&mut Self>) -> QString {
        let (url, title) = self.rust().last_join.clone();
        QString::from(json!({ "url": url.to_string(), "title": title.to_string() }).to_string().as_str())
    }

    pub fn move_meeting(self: Pin<&mut Self>, join_url: &QString, title: &QString) {
        let (url, title) = (join_url.to_string(), title.to_string());
        let qt = self.qt_thread();
        runtime().spawn(async move {
            // As Teams moves between meetings: the one we leave goes quiet
            // now and is left once the next one answers (join_meeting).
            let mut slot = call_slot().lock().await;
            if let Some(mut call) = slot.outgoing.take() {
                call.stop_media();
                if slot.left_calls.len() >= 16 {
                    slot.left_calls.remove(0);
                }
                slot.left_calls.push(call.call_id().to_string());
                if slot.left_tags.len() >= 16 {
                    slot.left_tags.remove(0);
                }
                slot.left_tags.push(call.call_tag().to_string());
                if let Some(earlier) = slot.moved_from.replace(call) {
                    runtime().spawn(leave_moved_from(earlier));
                }
            }
            drop(slot);
            tracing::info!("moving to another meeting");
            let _ = qt.queue(move |mut this| {
                this.as_mut().set_call_camera_on(false);
                this.as_mut().set_call_state(QString::default());
                this.as_mut().join_meeting(&QString::from(url.as_str()), &QString::from(title.as_str()));
            });
        });
    }

    pub fn open_lobby_chat(self: Pin<&mut Self>) {
        if !self.rust().call_lobby_thread.is_empty() {
            return;
        }
        let Some(link) = self.call_meeting_link() else {
            return;
        };
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let (tenant, organizer) = (link.tenant_id.clone().unwrap_or_default(), link.organizer_id.clone().unwrap_or_default());
            let result = async {
                let client = TeamsClient::new().await?;
                api::meeting_options::lobby_chat_thread(&client, &tenant, &organizer, &link.thread_id, &link.message_id).await
            }
            .await;
            match result {
                Ok(id) => {
                    tracing::info!("lobby chat thread ready");
                    let _ = qt.queue(move |mut this| this.as_mut().set_call_lobby_thread(QString::from(id.as_str())));
                }
                Err(e) => tracing::warn!("lobby chat: {}", short_error(&e)),
            }
        });
    }

    pub fn load_meeting_controls(self: Pin<&mut Self>) {
        let Some(link) = self.call_meeting_link() else {
            return;
        };
        let qt = self.qt_thread();
        runtime().spawn(async move { load_controls(qt, link, Vec::new()).await });
    }

    pub fn set_meeting_option(self: Pin<&mut Self>, name: &QString, value_json: &QString) {
        let Some(link) = self.call_meeting_link() else {
            return;
        };
        let Ok(value) = serde_json::from_str::<serde_json::Value>(&value_json.to_string()) else {
            return;
        };
        let qt = self.qt_thread();
        let name = name.to_string();
        runtime().spawn(async move { load_controls(qt, link, vec![(name, value)]).await });
    }

    pub fn set_meeting_options(self: Pin<&mut Self>, changes_json: &QString) {
        let Some(link) = self.call_meeting_link() else {
            return;
        };
        let Ok(serde_json::Value::Object(map)) = serde_json::from_str::<serde_json::Value>(&changes_json.to_string()) else {
            return;
        };
        let changes: Vec<(String, serde_json::Value)> = map.into_iter().collect();
        if changes.is_empty() {
            return;
        }
        let qt = self.qt_thread();
        runtime().spawn(async move { load_controls(qt, link, changes).await });
    }

    pub fn resolve_names(self: Pin<&mut Self>, mris_json: &QString) {
        let known: serde_json::Map<String, serde_json::Value> =
            serde_json::from_str(&self.rust().people_names_json.to_string()).unwrap_or_default();
        let mris: Vec<String> = serde_json::from_str::<Vec<String>>(&mris_json.to_string())
            .unwrap_or_default()
            .into_iter()
            .filter(|m| !known.contains_key(m))
            .collect();
        if mris.is_empty() {
            return;
        }
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let found = async {
                let client = TeamsClient::new().await?;
                api::directory::short_profiles(&client, &mris).await
            }
            .await;
            match found {
                Ok(found) if !found.is_empty() => {
                    let _ = qt.queue(move |mut this| {
                        let mut map: serde_json::Map<String, serde_json::Value> =
                            serde_json::from_str(&this.rust().people_names_json.to_string()).unwrap_or_default();
                        for (mri, name) in found {
                            map.insert(mri, json!(name));
                        }
                        let text = serde_json::Value::Object(map).to_string();
                        this.as_mut().set_people_names_json(QString::from(text.as_str()));
                    });
                }
                Ok(_) => {}
                Err(e) => tracing::warn!("names: {}", short_error(&e)),
            }
        });
    }

    pub fn rejoin_meeting(mut self: Pin<&mut Self>) {
        let (url, title) = self.rust().last_join.clone();
        if url.is_empty() {
            return;
        }
        if self.rust().call_state.to_string() == "ended" {
            self.as_mut().set_call_state(QString::default());
        }
        self.as_mut().join_meeting(&url, &title);
    }

    pub fn join_meeting(mut self: Pin<&mut Self>, join_url: &QString, title: &QString) {
        if !self.rust().call_state.is_empty() {
            return;
        }
        let Some(link) = outgoing::MeetingLink::parse(&join_url.to_string()) else {
            self.as_mut().set_status_text(QString::from(
                "That isn't a Teams meeting link OST can join",
            ));
            return;
        };
        // Breakout rooms are the last meeting's (but a held main
        // meeting's rooms stay managed from its room).
        self.as_mut().set_call_breakout_json(QString::default());
        if self.rust().call_held_meeting_json.is_empty() {
            self.as_mut().set_call_breakout_all_json(QString::default());
        }
        self.as_mut().set_call_breakout_room_json(QString::default());
        self.as_mut().set_call_breakout_rooms_json(QString::default());
        self.as_mut().reset_meeting_view(&link, join_url, title);
        self.as_mut().set_call_state(QString::from("connecting"));
        tracing::info!("join meeting");
        let qt = self.qt_thread();
        let (cancel_tx, cancel_rx) = tokio::sync::oneshot::channel();
        runtime().block_on(async { call_slot().lock().await.cancel_placing = Some(cancel_tx) });
        runtime().spawn(async move {
            let result = outgoing::join_meeting(&link, cancel_rx).await;
            let mut slot = call_slot().lock().await;
            slot.cancel_placing = None;
            match result {
                Ok(call) => {
                    let view = JoinedView::of(&call);
                    let in_lobby = call.in_lobby();
                    let (has_audio, can_dtmf, can_video, can_share) = (view.has_audio, view.can_dtmf, view.can_video, view.can_share);
                    tracing::info!(has_audio, can_dtmf, can_video, can_share, in_lobby, "meeting joined");
                    seed_roster(&qt, &call).await;
                    // Back in a meeting we had moved out of: its end is ours again.
                    let id = call.call_id().to_string();
                    slot.left_calls.retain(|left| *left != id);
                    slot.outgoing = Some(call);
                    // Moving between meetings: leave the last one now.
                    let moved_from = slot.moved_from.take();
                    drop(slot);
                    if let Some(earlier) = moved_from {
                        runtime().spawn(leave_moved_from(earlier));
                    }
                    spawn_call_stats_logger(qt.clone());
                    let _ = qt.queue(move |mut this| this.as_mut().show_joined(view, in_lobby));
                }
                Err(e) => {
                    let moved_from = slot.moved_from.take();
                    drop(slot);
                    if let Some(earlier) = moved_from {
                        runtime().spawn(leave_moved_from(earlier));
                    }
                    let msg = short_error(&e);
                    tracing::info!("meeting join ended: {msg}");
                    let _ = qt.queue(move |mut this| {
                        this.as_mut().set_status_text(QString::from(
                            format!("Couldn't join the meeting: {msg}").as_str(),
                        ));
                        this.as_mut().end_call_ui();
                    });
                }
            }
        });
    }

    pub fn participant_action(
        self: Pin<&mut Self>,
        action: &QString,
        id: &QString,
        name: &QString,
        state_id: &QString,
    ) {
        let (action, id, name, state) = (
            action.to_string(),
            id.to_string(),
            name.to_string(),
            state_id.to_string(),
        );
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let mut slot = call_slot().lock().await;
            let Some(call) = slot.outgoing.as_mut() else {
                return;
            };
            let result = match action.as_str() {
                "mute" => call.mute_participant(&id).await,
                "spotlight" => call.spotlight(&id, None).await,
                "unspotlight" => call.spotlight(&id, Some(&state)).await,
                "attendee" | "presenter" => call.set_role(&id, &action).await,
                "remove" => call.remove(&id, &name).await,
                _ => Ok(()),
            };
            drop(slot);
            if let Err(e) = result {
                tracing::warn!(action, "participant action: {}", short_error(&e));
                let _ = qt.queue(move |mut this| {
                    this.as_mut()
                        .set_status_text(QString::from(short_error(&e).as_str()))
                });
            }
        });
    }

    pub fn leave_on_all_devices(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        runtime().spawn(async move {
            if let Some(call) = call_slot().lock().await.outgoing.as_ref()
                && let Err(e) = call.remove_my_other_devices().await
            {
                tracing::warn!("leave on all devices: {}", short_error(&e));
            }
            // Then leave, as Teams does.
            let _ = qt.queue(|this| this.hang_up());
        });
    }

    pub fn hang_up(mut self: Pin<&mut Self>) {
        self.as_mut().end_call_ui();
        runtime().spawn(async {
            let mut slot = call_slot().lock().await;
            if let Some(earlier) = slot.moved_from.take() {
                runtime().spawn(leave_moved_from(earlier));
            }
            if let Some((held, _, _)) = slot.held_main.take() {
                runtime().spawn(leave_moved_from(held));
            }
            if let Some(cancel) = slot.cancel_placing.take() {
                let _ = cancel.send(());
                tracing::info!("outgoing call cancelled");
                return;
            }
            if let Some(call) = slot.outgoing.take() {
                drop(slot);
                if let Err(e) = call.hang_up().await {
                    tracing::warn!("hang up failed: {}", short_error(&e));
                }
                return;
            }
            let Some(call) = slot.active.take() else {
                return;
            };
            drop(slot);
            let result = async { CallAuth::load().await?.hang_up(call).await }.await;
            if let Err(e) = result {
                tracing::warn!("hang up failed: {}", short_error(&e));
            }
        });
    }

    pub fn send_reaction(self: Pin<&mut Self>, name: &QString) {
        let name = name.to_string();
        runtime().spawn(async move {
            let result = match call_slot().lock().await.outgoing.as_ref() {
                Some(call) => call.send_reaction(&name).await,
                None => return,
            };
            if let Err(e) = result {
                tracing::warn!("reaction failed: {}", short_error(&e));
            }
        });
    }

    pub fn set_video_widths(mut self: Pin<&mut Self>, json: &QString) {
        let widths: std::collections::HashMap<String, f64> =
            serde_json::from_str(&json.to_string()).unwrap_or_default();
        if widths == self.rust().video_widths {
            return;
        }
        self.as_mut().rust_mut().video_widths = widths;
        // Later, not inside the QML binding update that called us (the
        // roster sets properties that binding depends on).
        let _ = self.qt_thread().queue(|this| this.apply_roster(Vec::new()));
    }

    pub fn set_incoming_video(mut self: Pin<&mut Self>, on: bool) {
        if self.rust().incoming_video_off != on {
            return;
        }
        self.as_mut().rust_mut().incoming_video_off = !on;
        tracing::info!(on, "incoming video");
        self.apply_roster(Vec::new());
    }

    pub fn update_tray(
        self: Pin<&mut Self>,
        kind: &QString,
        status_label: &QString,
        name_line: &QString,
    ) {
        let (kind, label, name) = (
            kind.to_string(),
            status_label.to_string(),
            name_line.to_string(),
        );
        static TRAY: std::sync::OnceLock<
            tokio::sync::OnceCell<Option<ksni::Handle<crate::tray::OstTray>>>,
        > = std::sync::OnceLock::new();
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let cell = TRAY.get_or_init(tokio::sync::OnceCell::new);
            let handle = cell
                .get_or_init(|| async {
                    let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel();
                    let handle = crate::tray::spawn(crate::tray::OstTray::new(tx)).await;
                    // The tray's requests, done on the Qt thread.
                    tokio::spawn(async move {
                        while let Some(action) = rx.recv().await {
                            let _ = qt.queue(move |mut this| match action {
                                crate::tray::Action::Show => this.as_mut().tray_show(),
                                crate::tray::Action::Quit => this.as_mut().tray_quit(),
                                crate::tray::Action::CollectSupportFiles => {
                                    this.collect_support_files()
                                }
                                crate::tray::Action::Status(key) => {
                                    this.as_mut().set_my_status(&QString::from(key))
                                }
                            });
                        }
                    });
                    handle
                })
                .await;
            if let Some(h) = handle {
                h.update(|t| {
                    t.kind = kind;
                    t.status_label = label;
                    t.name_line = name;
                })
                .await;
            }
        });
    }

    pub fn mute_all(self: Pin<&mut Self>) {
        runtime().spawn(async move {
            let result = match call_slot().lock().await.outgoing.as_ref() {
                Some(call) => call.mute_all().await,
                None => return,
            };
            if let Err(e) = result {
                tracing::warn!("mute all failed: {}", short_error(&e));
            }
        });
    }

    /// Show the meeting's lock and attendee restrictions; `notify` for a
    /// change while we're in it (Teams' locked / unlocked notice).
    /// The call window set for a meeting about to be joined (or resumed):
    /// its title, links and an empty roster.
    fn reset_meeting_view(mut self: Pin<&mut Self>, link: &outgoing::MeetingLink, join_url: &QString, title: &QString) {
        let title = if title.is_empty() {
            QString::from("Meeting")
        } else {
            title.clone()
        };
        self.as_mut().rust_mut().last_join = (join_url.clone(), title.clone());
        self.as_mut().set_call_end_reason(QString::default());
        self.as_mut().set_call_peer(title);
        self.as_mut().set_call_peer_id(QString::default());
        self.as_mut().rust_mut().roster.clear();
        self.as_mut().set_call_roster_json(QString::from("[]"));
        self.as_mut().set_call_video_json(QString::from("{}"));
        self.as_mut().set_call_speaker_mri(QString::default());
        self.as_mut().set_call_speaking_json(QString::from("[]"));
        self.as_mut().set_call_muted_by_meeting(false);
        self.as_mut().set_call_share_mri(QString::default());
        self.as_mut().set_call_lobby_json(QString::from("[]"));
        self.as_mut().set_call_invite_url(QString::default());
        self.as_mut()
            .set_call_thread_id(QString::from(link.thread_id.as_str()));
        self.as_mut().load_call_chat_members();
        self.as_mut().set_call_options_url(QString::from(
            link.options_url().unwrap_or_default().as_str(),
        ));
        self.as_mut()
            .set_call_chat_url(QString::from(link.chat_url().as_str()));
        self.as_mut().set_call_meeting(true);
        self.as_mut().set_call_video_offered(false);
        self.as_mut().set_call_muted(false);
        self.as_mut().rust_mut().attendance = Default::default();
        self.as_mut().set_call_scheduled(true);
        self.as_mut().set_call_meeting_locked(false);
        self.as_mut().set_call_attendee_restrictions(0);
        self.as_mut().set_call_speaking_while_muted(false);
        self.as_mut().set_call_timer_json(QString::default());
        self.as_mut().set_call_ai_indicator(false);
        self.as_mut().set_call_ai_available(false);
        self.as_mut().set_call_ai_facilitator(false);
        self.as_mut().set_call_ai_on(false);
        self.as_mut().show_processing(Default::default());
        self.as_mut().set_call_meeting_info_json(QString::default());
        self.as_mut().set_call_lobby_thread(QString::default());
        self.as_mut().show_transcript(Vec::new(), true);
        self.as_mut().reset_captions();
    }

    /// The call window for a joined (or resumed) meeting.
    fn show_joined(mut self: Pin<&mut Self>, v: JoinedView, in_lobby: bool) {
        self.as_mut().set_call_invite_url(QString::from(v.invite.as_str()));
        self.as_mut().show_capability(v.capability, false);
        self.as_mut().rust_mut().timer_skew_ms = 0;
        self.as_mut().show_timers(v.timers, false);
        self.as_mut().show_processing(v.processing);
        self.as_mut().load_call_accessibility(true);
        self.as_mut().set_call_ai_indicator(v.ai_indicator);
        self.as_mut().set_call_has_audio(v.has_audio);
        self.as_mut().set_call_can_dtmf(v.can_dtmf);
        self.as_mut().set_call_can_video(v.can_video);
        self.as_mut().set_call_can_share(v.can_share);
        self.as_mut().set_call_lobby_presenter(v.started);
        // Held in the lobby: Teams keeps the pre-join screen until someone
        // admits us.
        self.as_mut().set_call_state(QString::from(if in_lobby { "lobby" } else { "connected" }));
    }

    fn show_capability(
        mut self: Pin<&mut Self>,
        cap: teams_cli::calling::meeting_options::MeetingCapability,
        notify: bool,
    ) {
        if self.rust().call_meeting_locked != cap.locked {
            self.as_mut().set_call_meeting_locked(cap.locked);
            if notify {
                let n = self.rust().call_lock_notices + 1;
                self.as_mut().set_call_lock_notices(n);
            }
        }
        let bits = cap.attendee_restrictions as i32;
        if self.rust().call_attendee_restrictions != bits {
            self.as_mut().set_call_attendee_restrictions(bits);
        }
        if self.rust().call_ai_available != cap.copilot {
            self.as_mut().set_call_ai_available(cap.copilot);
        }
        if self.rust().call_everyone_presents != cap.everyone_presents {
            self.as_mut().set_call_everyone_presents(cap.everyone_presents);
        }
        if self.rust().call_ai_facilitator != cap.facilitator {
            self.as_mut().set_call_ai_facilitator(cap.facilitator);
        }
    }

    /// Show what the meeting's call recorder does: AI is on while its
    /// transcript (or Copilot's) runs; the recording indicator names who
    /// started the recording and transcript.
    fn show_processing(mut self: Pin<&mut Self>, p: teams_cli::calling::roster::Processing) {
        let on = p.transcript.is_some() || p.copilot;
        if self.rust().call_ai_on != on {
            self.as_mut().set_call_ai_on(on);
        }
        self.as_mut().rust_mut().processing = p;
        self.as_mut().show_recording_indicator();
        self.as_mut().publish_captions_if_started();
    }

    /// The recording indicator's state and tooltip, with the starters'
    /// names from the roster (or ours).
    fn show_recording_indicator(mut self: Pin<&mut Self>) {
        let me = self.rust().user_mri.to_string().to_ascii_lowercase();
        let my_name = self.rust().user_name.to_string();
        let roster = &self.rust().roster;
        let p = &self.rust().processing;
        let tip = p.indicator_tooltip(|id| {
            let id = id.to_ascii_lowercase();
            roster
                .iter()
                .find(|x| x.id == id)
                .map(|x| x.name.clone())
                .filter(|n| !n.is_empty())
                .unwrap_or_else(|| if id == me { my_name.clone() } else { String::new() })
        });
        let state = QString::from(p.indicator_state());
        let tip = QString::from(tip.as_str());
        if self.rust().call_recording_state != state {
            self.as_mut().set_call_recording_state(state);
        }
        if self.rust().call_recording_tip != tip {
            self.as_mut().set_call_recording_tip(tip);
        }
    }

    pub fn meeting_action(self: Pin<&mut Self>, action: &QString) {
        let action = action.to_string();
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let mut slot = call_slot().lock().await;
            let Some(call) = slot.outgoing.as_mut() else {
                return;
            };
            let result = match action.as_str() {
                "lock" | "unlock" => {
                    call.update_meeting_settings(serde_json::json!({ "lockMeeting": action == "lock" }))
                        .await
                }
                "lowerHands" => call.remove_state_for_everyone("raiseHands").await,
                "stopSpotlights" => call.remove_state_for_everyone("spotlight").await,
                _ => Ok(()),
            };
            drop(slot);
            if let Err(e) = result {
                tracing::warn!(action, "meeting action: {}", short_error(&e));
                // Teams: "Couldn't lock the meeting" with Try again.
                let failed = action.clone();
                let _ = qt.queue(move |this| {
                    this.meeting_action_failed(QString::from(failed.as_str()))
                });
            }
        });
    }

    pub fn set_attendee_restrictions(self: Pin<&mut Self>, bits: i32) {
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = match call_slot().lock().await.outgoing.as_mut() {
                Some(call) => {
                    call.update_meeting_settings(serde_json::json!({ "attendeeRestrictions": bits }))
                        .await
                }
                None => return,
            };
            if let Err(e) = result {
                tracing::warn!(bits, "attendee restrictions: {}", short_error(&e));
                let _ = qt.queue(move |mut this| {
                    this.as_mut()
                        .set_status_text(QString::from(short_error(&e).as_str()))
                });
            }
        });
    }

    pub fn recorder_command(self: Pin<&mut Self>, command: &QString, language: &QString, audio_only: bool) {
        use teams_cli::calling::recorder::{Command, Meeting};
        let name = command.to_string();
        let transcribing = self.rust().processing.transcript.is_some();
        let cmd = match name.as_str() {
            "startTranscription" => Command::StartTranscription,
            "stopTranscription" => Command::StopTranscription,
            "startRecording" if transcribing => Command::StartRecordingOnly { audio_only },
            "startRecording" => Command::StartRecording { audio_only },
            "stopRecording" => Command::StopRecording,
            _ => return,
        };
        // The organizer as the roster names them (else us).
        let organizer = self
            .rust()
            .roster
            .iter()
            .find(|p| p.role.eq_ignore_ascii_case("organizer"))
            .map(|p| p.name.clone())
            .filter(|n| !n.is_empty())
            .unwrap_or_else(|| self.rust().user_name.to_string());
        let language = language.to_string();
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let Some(info) = call_slot().lock().await.outgoing.as_ref().map(|c| c.meeting_info().unwrap_or_default()) else {
                return;
            };
            let meeting = Meeting {
                title: info.title,
                ical_uid: info.ical_uid,
                organizer,
                spoken_language: language,
            };
            let result = match ensure_recorder(&meeting).await {
                Ok(()) => match call_slot().lock().await.outgoing.as_ref() {
                    Some(call) => call.recorder_command(cmd, &meeting).await,
                    None => return,
                },
                Err(e) => Err(e),
            };
            if let Err(e) = result {
                tracing::warn!(command = %name, "recorder: {}", short_error(&e));
                let _ = qt.queue(move |this| this.meeting_action_failed(QString::from(name.as_str())));
            }
        });
    }

    /// Add rows to the Transcript pane (`reset`: start over).
    fn show_transcript(mut self: Pin<&mut Self>, rows: Vec<teams_cli::calling::transcript::Entry>, reset: bool) {
        if reset {
            self.as_mut().rust_mut().transcript.clear();
        }
        let now = chrono::Utc::now().timestamp_millis();
        teams_cli::calling::transcript::merge_live(&mut self.as_mut().rust_mut().transcript, rows, now);
        let json = serde_json::to_string(&self.rust().transcript).unwrap_or_else(|_| "[]".into());
        if self.rust().call_transcript_json.to_string() != json {
            self.as_mut().set_call_transcript_json(QString::from(json.as_str()));
        }
    }

    fn show_captions(mut self: Pin<&mut Self>, rows: Vec<teams_cli::calling::transcript::Entry>) {
        let now = chrono::Utc::now().timestamp_millis();
        teams_cli::calling::transcript::merge_captions(&mut self.as_mut().rust_mut().captions, rows, now);
        self.publish_captions();
    }

    /// The captions window's list: captions and ended RTT lines in time
    /// order, then the RTT lines being typed (yours last).
    fn publish_captions(mut self: Pin<&mut Self>) {
        let me = self.rust().user_mri.to_string();
        let mut rows = self.rust().captions.clone();
        rows.extend(teams_cli::calling::rtt::typing_order(&self.rust().rtt_typing, &me));
        let json = serde_json::to_string(&rows).unwrap_or_else(|_| "[]".into());
        if self.rust().call_captions_json.to_string() != json {
            self.as_mut().set_call_captions_json(QString::from(json.as_str()));
        }
    }

    /// Forget the last call's captions (a new call starts without them).
    fn reset_captions(mut self: Pin<&mut Self>) {
        // A new call starts with notifications allowed.
        self.as_mut().set_call_notifications_muted(false);
        self.as_mut().set_call_chat_bubbles_suppressed(false);
        self.as_mut().rust_mut().captions.clear();
        self.as_mut().rust_mut().captions_published = false;
        self.as_mut().rust_mut().rtt_lines.clear();
        self.as_mut().rust_mut().rtt_typing.clear();
        self.as_mut().rust_mut().rtt_box.clear();
        self.as_mut().set_call_rtt_on(false);
        self.as_mut().set_call_rtt_initiator(false);
        self.as_mut().set_call_captions_json(QString::from("[]"));
        self.as_mut().set_call_captions_on(false);
    }

    fn show_timers(mut self: Pin<&mut Self>, t: teams_cli::calling::meeting_timer::Timers, live: bool) {
        let json = serde_json::json!({
            "adhoc": t.adhoc.0,
            "lastEditMs": t.adhoc.last_edit_ms(),
            "totalMs": t.adhoc.total_ms(),
            "skewMs": self.rust().timer_skew_ms,
            "sequence": t.sequence,
            "live": live,
            "facilitator": self.rust().call_ai_facilitator,
        });
        self.as_mut().set_call_timer_json(QString::from(json.to_string().as_str()));
    }

    pub fn meeting_timer(self: Pin<&mut Self>, action: &QString, arg: i32) {
        let action = action.to_string();
        let skew = self.rust().timer_skew_ms;
        runtime().spawn(async move {
            let slot = call_slot().lock().await;
            let Some(call) = slot.outgoing.as_ref() else { return };
            let now = chrono::Utc::now().timestamp_millis();
            let t = &call.timers().adhoc;
            let next = match action.as_str() {
                "start" => t.start(),
                "pause" => t.pause(),
                "resume" => t.resume(),
                "reset" => t.reset(),
                "cancel" => t.cancel(),
                "cancelOverTime" => t.cancel_over_time(),
                "startWith" => t.start_with(i64::from(arg).clamp(0, teams_cli::calling::meeting_timer::MAX_MS)),
                "add" => t.add_minutes(i64::from(arg), now, skew),
                other => {
                    tracing::warn!(other, "meeting timer: unknown action");
                    return;
                }
            };
            if let Err(e) = call.publish_timer(&next).await {
                tracing::warn!("meeting timer: {}", short_error(&e));
            }
        });
    }

    pub fn call_health_refresh(mut self: Pin<&mut Self>) {
        let state = teams_cli::calling::call_health::MediaState {
            microphone: !self.rust().call_muted && self.rust().call_has_audio,
            camera: self.rust().call_camera_on,
            sharing: self.rust().call_sharing,
            watching_share: !self.rust().call_share_mri.is_empty(),
        };
        let report = health_sampler()
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .report(&teams_cli::calling::call_health::current(), &state);
        let json = serde_json::json!({ "values": report.values }).to_string();
        if self.rust().call_health_json.to_string() != json {
            self.as_mut().set_call_health_json(QString::from(json.as_str()));
        }
    }

    pub fn timer_chime(&self) {
        teams_cli::calling::ringtone::chime();
    }

    /// RTT turns on for this call: by you, or with someone's first words.
    /// The captions window opens on its card.
    fn turn_rtt_on(mut self: Pin<&mut Self>, initiator: bool) {
        if self.rust().call_rtt_on {
            return;
        }
        tracing::info!(initiator, "real-time text on");
        self.as_mut().set_call_rtt_initiator(initiator);
        self.as_mut().set_call_rtt_on(true);
        let now = chrono::Utc::now().timestamp_millis();
        teams_cli::calling::transcript::merge_captions(
            &mut self.as_mut().rust_mut().captions,
            vec![teams_cli::calling::rtt::intro(now)],
            now,
        );
        self.as_mut().publish_captions();
        if self.rust().call_privacy_url.is_empty() {
            let qt = self.qt_thread();
            runtime().spawn(async move {
                let url = match TeamsClient::new().await {
                    Ok(client) => api::directory::privacy_statement_url(&client).await,
                    Err(_) => api::directory::MICROSOFT_PRIVACY_STATEMENT.to_string(),
                };
                let _ = qt.queue(move |mut this| this.as_mut().set_call_privacy_url(QString::from(url.as_str())));
            });
        }
    }

    pub fn start_rtt(self: Pin<&mut Self>) {
        self.turn_rtt_on(true);
    }

    /// Show RTT lines as they changed.
    fn show_rtt(mut self: Pin<&mut Self>, updates: Vec<teams_cli::calling::rtt::Update>) {
        if updates.is_empty() {
            return;
        }
        let now = chrono::Utc::now().timestamp_millis();
        let mut typing = std::mem::take(&mut self.as_mut().rust_mut().rtt_typing);
        let mut window = std::mem::take(&mut self.as_mut().rust_mut().captions);
        for u in &updates {
            teams_cli::calling::rtt::show(u, &mut typing, &mut window, now);
        }
        self.as_mut().rust_mut().rtt_typing = typing;
        self.as_mut().rust_mut().captions = window;
        self.publish_captions();
    }

    /// Someone's real-time text arrived from data source `source`.
    fn receive_rtt(mut self: Pin<&mut Self>, source: u32, text: String, own_source: Option<u32>) {
        let (user_id, name) = self
            .rust()
            .roster
            .iter()
            .find(|p| p.data_sources.contains(&i64::from(source)))
            .map(|p| (p.id.clone(), p.name.clone()))
            .unwrap_or_default();
        let now = chrono::Utc::now().timestamp_millis();
        let updates = self.as_mut().rust_mut().rtt_lines.receive(source, &user_id, &name, &text, now);
        if !self.rust().call_rtt_on && updates.iter().any(|u| !u.text.is_empty()) {
            self.as_mut().turn_rtt_on(false);
        }
        if !self.rust().call_rtt_on {
            return;
        }
        // You, typing on another device: Teams empties this one's box.
        let me = self.rust().user_mri.to_string();
        let mine_elsewhere = updates
            .iter()
            .any(|u| u.user_id.eq_ignore_ascii_case(&me) && Some(u.source) != own_source && !u.text.is_empty());
        self.as_mut().show_rtt(updates);
        if mine_elsewhere && !self.rust().rtt_box.is_empty() {
            self.as_mut().rust_mut().rtt_box.clear();
            self.as_mut().rtt_input_cleared();
        }
    }

    /// Send our RTT chunk and show it as typed (Teams shows its own at
    /// once rather than as it comes back).
    fn send_rtt_chunk(mut self: Pin<&mut Self>, chunk: String) {
        let me = self.rust().user_mri.to_string();
        let name = self.rust().user_name.to_string();
        let now = chrono::Utc::now().timestamp_millis();
        let updates = self.as_mut().rust_mut().rtt_lines.receive(OWN_RTT_SOURCE, &me, &name, &chunk, now);
        self.as_mut().show_rtt(updates);
        let _ = rtt_outbox().send(chunk);
    }

    pub fn rtt_input(mut self: Pin<&mut Self>, text: &QString) -> bool {
        self.as_mut().rust_mut().rtt_box.changed(&text.to_string())
    }

    pub fn rtt_flush(mut self: Pin<&mut Self>) -> bool {
        if !self.rust().call_rtt_on {
            return false;
        }
        match self.as_mut().rust_mut().rtt_box.flush() {
            Some(chunk) => {
                self.send_rtt_chunk(chunk);
                true
            }
            None => false,
        }
    }

    pub fn rtt_commit(mut self: Pin<&mut Self>, manual: bool) -> bool {
        match self.as_mut().rust_mut().rtt_box.commit(manual) {
            Ok(Some(chunk)) if self.rust().call_rtt_on => {
                self.send_rtt_chunk(chunk);
                true
            }
            Ok(_) => true,
            Err(teams_cli::calling::rtt::OnlySpaces) => false,
        }
    }

    pub fn set_captions(mut self: Pin<&mut Self>, on: bool) {
        if self.rust().call_captions_on == on {
            return;
        }
        self.as_mut().set_call_captions_on(on);
        let running = self.rust().processing.captions;
        if !on {
            // RTT's lines stay in the window.
            self.as_mut().rust_mut().captions.retain(|e| {
                matches!(
                    e.kind,
                    teams_cli::calling::transcript::Kind::RealTimeText
                        | teams_cli::calling::transcript::Kind::RealTimeTextIntro
                )
            });
            self.as_mut().publish_captions();
        }
        let was_published = self.rust().captions_published;
        let language = self.rust().call_captions_language.to_string();
        let organizer = self
            .rust()
            .roster
            .iter()
            .find(|p| p.role.eq_ignore_ascii_case("organizer"))
            .map(|p| p.name.clone())
            .filter(|n| !n.is_empty())
            .unwrap_or_else(|| self.rust().user_name.to_string());
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = if !on {
                // Teams sends no stop: the recorder stops captions once no
                // endpoint wants them.
                match call_slot().lock().await.outgoing.as_ref() {
                    Some(call) if was_published => call.publish_captions_pref(false).await,
                    _ => Ok(()),
                }
            } else if running {
                match call_slot().lock().await.outgoing.as_ref() {
                    Some(call) => call.publish_captions_pref(true).await,
                    None => return,
                }
            } else {
                let info = call_slot().lock().await.outgoing.as_ref().and_then(|c| c.meeting_info()).unwrap_or_default();
                let meeting = teams_cli::calling::recorder::Meeting {
                    title: info.title,
                    ical_uid: info.ical_uid,
                    organizer,
                    spoken_language: if language.is_empty() { "en-us".into() } else { language },
                };
                match ensure_recorder(&meeting).await {
                    Ok(()) => match call_slot().lock().await.outgoing.as_ref() {
                        Some(call) => call.recorder_command(teams_cli::calling::recorder::Command::StartCaptions, &meeting).await,
                        None => return,
                    },
                    Err(e) => Err(e),
                }
            };
            let published = on && running;
            let _ = qt.queue(move |mut this| match result {
                Ok(()) => this.as_mut().rust_mut().captions_published = published,
                Err(e) => {
                    tracing::warn!(on, "captions: {}", short_error(&e));
                    if on {
                        this.as_mut().set_call_captions_on(false);
                        this.meeting_action_failed(QString::from("startCaptions"));
                    }
                }
            });
        });
    }

    /// Once the recorder runs captions for a meeting where we turned them
    /// on, say so in our endpoint metadata (Teams' setStatus(started)).
    fn publish_captions_if_started(mut self: Pin<&mut Self>) {
        if !(self.rust().call_captions_on && self.rust().processing.captions && !self.rust().captions_published) {
            return;
        }
        self.as_mut().rust_mut().captions_published = true;
        runtime().spawn(async move {
            if let Some(call) = call_slot().lock().await.outgoing.as_ref()
                && let Err(e) = call.publish_captions_pref(true).await
            {
                tracing::warn!("captions metadata: {}", short_error(&e));
            }
        });
    }

    pub fn set_captions_language(mut self: Pin<&mut Self>, language: &QString) {
        let language = language.to_string();
        self.as_mut().set_call_captions_language(QString::from(language.as_str()));
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let slot = call_slot().lock().await;
            let Some(call) = slot.outgoing.as_ref() else { return };
            let meeting = teams_cli::calling::recorder::Meeting { spoken_language: language, ..Default::default() };
            let result = call
                .recorder_command(teams_cli::calling::recorder::Command::SetCaptionsLanguage, &meeting)
                .await;
            drop(slot);
            if let Err(e) = result {
                tracing::warn!("captions language: {}", short_error(&e));
                let _ = qt.queue(|this| this.meeting_action_failed(QString::from("setCaptionsLanguage")));
            }
        });
    }

    pub fn update_call_accessibility(self: Pin<&mut Self>, patch: &QString) {
        let Ok(patch) = serde_json::from_str::<serde_json::Value>(&patch.to_string()) else { return };
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                api::preferences::update_call_accessibility_settings(&client, &patch).await
            }
            .await;
            match result {
                Ok(all) => {
                    let json = all.to_string();
                    let _ = qt.queue(move |mut this| {
                        this.as_mut().set_call_accessibility_json(QString::from(json.as_str()))
                    });
                }
                Err(e) => tracing::warn!("accessibility settings: {}", short_error(&e)),
            }
        });
    }

    /// Read the calling accessibility settings; with "Always turn on
    /// captions" set, turn captions on once the meeting is joined.
    fn load_call_accessibility(self: Pin<&mut Self>, start_captions: bool) {
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                api::preferences::call_accessibility_settings(&client).await
            }
            .await;
            let all = match result {
                Ok(v) => v,
                Err(e) => {
                    tracing::warn!("accessibility settings: {}", short_error(&e));
                    api::preferences::call_accessibility_defaults()
                }
            };
            let auto = all.get("startCaptionsAutomatically").and_then(|v| v.as_bool()) == Some(true);
            let json = all.to_string();
            let _ = qt.queue(move |mut this| {
                this.as_mut().set_call_accessibility_json(QString::from(json.as_str()));
                if start_captions && auto {
                    tracing::info!("captions: always on");
                    this.set_captions(true);
                }
            });
        });
    }

    pub fn load_transcript(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = match call_slot().lock().await.outgoing.as_ref() {
                Some(call) => call.transcript_history().await,
                None => return,
            };
            match result {
                Ok(rows) => {
                    tracing::info!(rows = rows.len(), "transcript history");
                    let _ = qt.queue(move |this| this.show_transcript(rows, false));
                }
                Err(e) => tracing::warn!("transcript history: {}", short_error(&e)),
            }
        });
    }

    pub fn load_meeting_info(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        runtime().spawn(async move {
            use teams_cli::calling::meeting_info as mi;
            let Some(info) = call_slot().lock().await.outgoing.as_ref().and_then(|c| c.meeting_info()) else {
                return;
            };
            let event = if info.ical_uid.is_empty() {
                None
            } else {
                match async {
                    let client = TeamsClient::new().await?;
                    api::calendar::event_by_ical_uid(&client, &info.ical_uid).await
                }
                .await
                {
                    Ok(e) => e,
                    Err(e) => {
                        tracing::warn!("meeting info: {}", short_error(&e));
                        None
                    }
                }
            };
            let tz = chrono::Local;
            let hours = match (info.start, info.end) {
                (Some(s), Some(e)) => mi::hours_text(s, e, &tz),
                _ => None,
            };
            let schedule = match (info.start, info.end) {
                (Some(s), Some(e)) => event
                    .as_ref()
                    .and_then(|ev| ev.recurrence.as_ref())
                    .and_then(|r| mi::recurrence_text(r, s, &tz))
                    .or_else(|| Some(mi::single_schedule_text(s, e, &tz))),
                _ => None,
            };
            let body = event.as_ref().map(|e| e.body_html.clone()).unwrap_or_default();
            let copy = mi::copy_join_info(&body, &info.join_url);
            // "Nov 6, 3:00 PM", as the report dialog's meeting card shows it.
            let start_text = info
                .start
                .map(|t| t.with_timezone(&tz).format("%b %-d, %-I:%M %p").to_string())
                .unwrap_or_default();
            let json = serde_json::json!({
                "title": info.title,
                // The scheduled times (the pre-join screen's date line while
                // we wait in the lobby).
                "start": info.start.map(|t| t.to_rfc3339()).unwrap_or_default(),
                "end": info.end.map(|t| t.to_rfc3339()).unwrap_or_default(),
                "startText": start_text,
                "hours": hours.unwrap_or_default(),
                "schedule": schedule.unwrap_or_default(),
                "location": info.location,
                "body": mi::body_for_display(&body),
                "canCopy": !copy.0.is_empty(),
            })
            .to_string();
            tracing::info!(has_event = event.is_some(), body = body.len(), "meeting info loaded");
            let _ = qt.queue(move |mut this| {
                this.as_mut().rust_mut().meeting_join_info = copy;
                this.as_mut().set_call_meeting_info_json(QString::from(json.as_str()));
            });
        });
    }

    pub fn copy_meeting_join_info(self: Pin<&mut Self>) {
        let (html, text) = self.rust().meeting_join_info.clone();
        if let (Ok(t), Ok(h)) = (std::ffi::CString::new(text), std::ffi::CString::new(html)) {
            // SAFETY: two NUL-terminated strings, copied by Qt before returning.
            unsafe { ost_set_clipboard(t.as_ptr(), h.as_ptr()) };
        }
    }

    pub fn download_attendance_list(mut self: Pin<&mut Self>) {
        let Some(dir) = download_dir() else { return };
        let bytes = teams_cli::calling::meeting_options::utf16le_with_bom(
            &self.rust().attendance.tsv(),
        );
        let msg = match teams_cli::api::files::save_unique(&dir, "meetingAttendanceList.csv", &bytes) {
            Ok(path) => {
                tracing::info!(path = %path.display(), "attendance list saved");
                format!(
                    "Saved {} to {}",
                    path.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default(),
                    dir.display()
                )
            }
            Err(e) => format!("Couldn't save the attendance list: {}", short_error(&e)),
        };
        self.as_mut().set_status_text(QString::from(msg.as_str()));
    }

    pub fn load_attendance(
        mut self: Pin<&mut Self>,
        thread: &QString,
        organizer: &QString,
        message: &QString,
        call_id: &QString,
    ) {
        let (thread, organizer, message, call) =
            (thread.to_string(), organizer.to_string(), message.to_string(), call_id.to_string());
        let key = format!("{thread}|{message}");
        // Keep the history while another report loads.
        let mut state: serde_json::Value =
            serde_json::from_str(&self.rust().attendance_json.to_string()).unwrap_or(json!({}));
        if state["key"] != json!(key) {
            state = json!({ "key": key, "reports": [] });
        }
        state["loading"] = json!(true);
        state["error"] = json!("");
        state["callId"] = json!(call);
        self.as_mut().set_attendance_json(QString::from(state.to_string().as_str()));
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let message = (!message.is_empty()).then_some(message);
            let result = async {
                let client = TeamsClient::new().await?;
                let reports = api::attendance::history(&client, &thread, &organizer, message.as_deref()).await?;
                // A chat's call-ended message names the call by its
                // ngcCallId; the reports go by their own callId.
                let call = if call.is_empty() {
                    reports.first().and_then(|r| r["callId"].as_str()).unwrap_or_default().to_string()
                } else {
                    reports
                        .iter()
                        .find(|r| r["callId"].as_str() == Some(&call) || r["ngcCallId"].as_str() == Some(&call))
                        .and_then(|r| r["callId"].as_str())
                        .map(str::to_string)
                        .unwrap_or(call)
                };
                let report = if call.is_empty() {
                    serde_json::Value::Null
                } else {
                    api::attendance::report(&client, &thread, &call, &organizer, message.as_deref()).await?
                };
                anyhow::Ok((reports, call, report))
            }
            .await;
            let _ = qt.queue(move |mut this| {
                let mut state: serde_json::Value =
                    serde_json::from_str(&this.rust().attendance_json.to_string()).unwrap_or(json!({}));
                if state["key"] != json!(key) {
                    return;
                }
                state["loading"] = json!(false);
                match result {
                    Ok((reports, call, report)) => {
                        state["reports"] = json!(reports);
                        state["callId"] = json!(call);
                        state["report"] = report;
                    }
                    Err(e) => {
                        tracing::warn!("attendance: {}", short_error(&e));
                        state["error"] = json!(short_error(&e));
                    }
                }
                this.as_mut().set_attendance_json(QString::from(state.to_string().as_str()));
            });
        });
    }

    pub fn download_attendance_report(mut self: Pin<&mut Self>, thread: &QString, organizer: &QString, call_id: &QString) {
        let Some(dir) = download_dir() else { return };
        let (thread, organizer, call) = (thread.to_string(), organizer.to_string(), call_id.to_string());
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                let (name, bytes) = api::attendance::file(&client, &thread, &call, &organizer).await?;
                let name = name.unwrap_or_else(|| "Attendance report.csv".to_string());
                api::files::save_unique(&dir, &name, &bytes)
            }
            .await;
            let msg = match result {
                Ok(path) => {
                    tracing::info!(path = %path.display(), "attendance report saved");
                    format!(
                        "Saved {} to {}",
                        path.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default(),
                        dir.display()
                    )
                }
                Err(e) => format!("Couldn't download the attendance report: {}", short_error(&e)),
            };
            let _ = qt.queue(move |mut this| this.as_mut().set_status_text(QString::from(msg.as_str())));
        });
    }

    pub fn end_meeting(mut self: Pin<&mut Self>) {
        self.as_mut().end_call_ui();
        runtime().spawn(async {
            let mut slot = call_slot().lock().await;
            let Some(call) = slot.outgoing.take() else {
                return;
            };
            drop(slot);
            if let Err(e) = call.end_for_everyone().await {
                tracing::warn!("end meeting failed: {}", short_error(&e));
            }
        });
    }

    pub fn video_devices(self: Pin<&mut Self>) -> QString {
        let devices = teams_cli::calling::camera::list_devices();
        let current = camera_device()
            .filter(|c| devices.iter().any(|(p, _)| p == c))
            .or_else(|| devices.first().map(|(p, _)| p.clone()))
            .unwrap_or_default();
        let list: Vec<serde_json::Value> = devices
            .iter()
            .map(|(path, name)| serde_json::json!({ "path": path, "name": name }))
            .collect();
        QString::from(serde_json::json!({ "devices": list, "current": current }).to_string().as_str())
    }

    pub fn set_camera_device(mut self: Pin<&mut Self>, path: &QString) {
        let path = path.to_string();
        self.as_mut().set_setting(&QString::from("cameraDevice"), &QString::from(path.as_str()));
        if !self.rust().call_camera_on {
            return;
        }
        // The camera is on: capture from the new one, the line unchanged.
        runtime().spawn(async move {
            let mut guard = call_slot().lock().await;
            let Some(mut call) = MediaCall::of(&mut guard) else {
                return;
            };
            let switched = either!(&mut call, c => c.set_camera(false, None))
                .and_then(|()| either!(&mut call, c => c.set_camera(true, Some(path.clone()))));
            if let Err(e) = switched {
                tracing::info!("switching camera: {}", short_error(&e));
            } else {
                tracing::info!(path, "camera switched");
            }
        });
    }

    pub fn set_camera_preview(self: Pin<&mut Self>, on: bool) -> bool {
        static PREVIEW: OnceLock<
            std::sync::Mutex<Option<teams_cli::calling::webrtc_video::CameraPreview>>,
        > = OnceLock::new();
        let mut p = PREVIEW
            .get_or_init(Default::default)
            .lock()
            .unwrap_or_else(|e| e.into_inner());
        *p = None;
        if !on {
            return true;
        }
        match teams_cli::calling::webrtc_video::CameraPreview::start(camera_device()) {
            Ok(preview) => {
                *p = Some(preview);
                true
            }
            Err(e) => {
                tracing::info!("camera preview: {}", short_error(&e));
                false
            }
        }
    }

    pub fn toggle_camera(self: Pin<&mut Self>) {
        let on = !self.rust().call_camera_on;
        let device = camera_device();
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let mut guard = call_slot().lock().await;
            let slot = &mut *guard;
            let Some(mut call) = MediaCall::of(slot) else {
                return;
            };
            // As Teams does, the camera line sends only while the camera
            // is on: turning it on is offered first (it starts once
            // answered, in reoffer_reply); turning it off stops it, then
            // tells the call.
            let result = if call.describes_media() {
                // A meeting: the camera starts (or stops), then the
                // meeting is told.
                match either!(&mut call, c => c.set_camera(on, device)) {
                    Ok(()) => match describe_media(slot.outgoing.as_ref()).await {
                        Ok(()) => Ok(Some(on)),
                        Err(e) => {
                            if on && let Some(mut call) = MediaCall::of(slot) {
                                let _ = either!(&mut call, c => c.set_camera(false, None));
                            }
                            Err(e)
                        }
                    },
                    Err(e) => Err(e),
                }
            } else if call.can_reoffer() {
                if on {
                    call.offer_media(Reoffer::Camera(true)).await.map(|()| None)
                } else {
                    match call.set_camera(false) {
                        Ok(()) => call
                            .offer_media(Reoffer::Camera(false))
                            .await
                            .map(|()| Some(false)),
                        Err(e) => Err(e),
                    }
                }
            } else {
                either!(&mut call, c => c.set_camera(on, device)).map(|()| Some(on))
            };
            drop(guard);
            let _ = qt.queue(move |mut this| match result {
                Ok(Some(c)) => this.as_mut().set_call_camera_on(c),
                Ok(None) => {}
                Err(e) => {
                    tracing::info!("camera: {}", short_error(&e));
                    this.as_mut().set_status_text(QString::from(
                        format!("Camera: {}", short_error(&e)).as_str(),
                    ));
                }
            });
        });
    }

    pub fn toggle_mute(mut self: Pin<&mut Self>) {
        let muted = !self.rust().call_muted;
        let qt = self.qt_thread();
        self.as_mut().rust_mut().unmute_pending = false;
        runtime().spawn(async move {
            let slot = call_slot().lock().await;
            if let Some(call) = slot.active.as_ref() {
                call.set_muted(muted);
            }
            // The meeting muted us: unmuting asks it first; the mic opens
            // when the roster says it let us (on_call_event).
            let ask = !muted && slot.outgoing.as_ref().is_some_and(|c| c.is_server_muted());
            if let Some(call) = slot.outgoing.as_ref() {
                if !ask {
                    call.set_muted(muted);
                }
                // Others see it, as in Teams.
                if let Err(e) = call.publish_mute(muted).await {
                    tracing::warn!("mute state: {}", short_error(&e));
                }
            }
            drop(slot);
            let _ = qt.queue(move |mut this| {
                if ask {
                    this.as_mut().rust_mut().unmute_pending = true;
                } else {
                    this.as_mut().set_call_muted(muted);
                }
            });
        });
    }

    pub fn toggle_hold(mut self: Pin<&mut Self>) {
        let held = !self.rust().call_held;
        self.as_mut().set_call_held(held);
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let mut guard = call_slot().lock().await;
            let slot = &mut *guard;
            let result = match (slot.active.as_mut(), slot.outgoing.as_mut()) {
                (Some(call), _) => match CallAuth::load().await {
                    Ok(auth) => call.hold(&auth, held).await,
                    Err(e) => Err(e),
                },
                (None, Some(call)) => call.hold(held).await,
                _ => Err(anyhow::anyhow!("No call")),
            };
            drop(guard);
            if let Err(e) = result {
                tracing::warn!("hold: {}", short_error(&e));
                let _ = qt.queue(move |mut this| {
                    this.as_mut().set_call_held(!held);
                    this.as_mut().set_status_text(QString::from(
                        format!("Hold: {}", short_error(&e)).as_str(),
                    ));
                });
            }
        });
    }

    pub fn toggle_share(self: Pin<&mut Self>) {
        let on = !self.rust().call_sharing;
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = if on {
                offer_screen().await
            } else {
                stop_screen().await.map(|()| false)
            };
            if let Ok(true) = result {
                // Sharing in a meeting: it started at once.
                let _ = qt.queue(|mut this| this.as_mut().set_call_sharing(true));
                spawn_share_watch(qt.clone());
            } else if let Err(e) = result {
                tracing::warn!("share: {}", short_error(&e));
                let _ = qt.queue(move |mut this| {
                    this.as_mut().set_status_text(QString::from(
                        format!("Share: {}", short_error(&e)).as_str(),
                    ));
                });
            } else if !on {
                let _ = qt.queue(|mut this| this.as_mut().set_call_sharing(false));
            }
        });
    }

    pub fn use_no_audio(mut self: Pin<&mut Self>) {
        self.as_mut().set_call_has_audio(false);
        runtime().spawn(async move {
            let slot = call_slot().lock().await;
            // Media only: nothing sent or played, the call stays as it is.
            if let Some(call) = slot.outgoing.as_ref() {
                call.set_held(true);
            }
            if let Some(call) = slot.active.as_ref() {
                call.set_held(true);
            }
        });
    }

    pub fn admit_from_lobby(self: Pin<&mut Self>, id: &QString, name: &QString, not_bot: bool) {
        let (id, name) = (id.to_string(), name.to_string());
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = match call_slot().lock().await.outgoing.as_ref() {
                Some(call) => call.admit(&id, &name, not_bot).await,
                None => return,
            };
            if let Err(e) = result {
                tracing::warn!("admit failed: {}", short_error(&e));
            }
            refresh_lobby(qt).await;
        });
    }

    pub fn deny_from_lobby(self: Pin<&mut Self>, id: &QString, name: &QString) {
        let (id, name) = (id.to_string(), name.to_string());
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = match call_slot().lock().await.outgoing.as_ref() {
                Some(call) => call.remove(&id, &name).await,
                None => return,
            };
            if let Err(e) = result {
                tracing::warn!("deny failed: {}", short_error(&e));
            }
            refresh_lobby(qt).await;
        });
    }

    pub fn admit_all_from_lobby(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = match call_slot().lock().await.outgoing.as_ref() {
                Some(call) => call.admit_all().await,
                None => return,
            };
            if let Err(e) = result {
                tracing::warn!("admit all failed: {}", short_error(&e));
            }
            refresh_lobby(qt).await;
        });
    }

    pub fn toggle_hand(mut self: Pin<&mut Self>) {
        let up = !self.rust().call_hand_raised;
        self.as_mut().set_call_hand_raised(up);
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let mut slot = call_slot().lock().await;
            let result = match slot.outgoing.as_mut() {
                Some(call) => call.raise_hand(up).await,
                None => Err(anyhow::anyhow!("Raise hand is for meetings")),
            };
            drop(slot);
            if let Err(e) = result {
                tracing::warn!("raise hand: {}", short_error(&e));
                let _ = qt.queue(move |mut this| {
                    this.as_mut().set_call_hand_raised(!up);
                    this.as_mut().set_status_text(QString::from(
                        format!("Raise: {}", short_error(&e)).as_str(),
                    ));
                });
            }
        });
    }

    pub fn transfer_call(self: Pin<&mut Self>, oid: &QString) {
        let target = format!("8:orgid:{}", oid.to_string().trim());
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let slot = call_slot().lock().await;
            let result = match (slot.active.as_ref(), slot.outgoing.as_ref()) {
                (Some(call), _) => match CallAuth::load().await {
                    Ok(auth) => call.transfer(&auth, &target).await,
                    Err(e) => Err(e),
                },
                (None, Some(call)) => call.transfer(&target).await,
                _ => Err(anyhow::anyhow!("No call")),
            };
            drop(slot);
            let text = match &result {
                Ok(()) => "Transferring…".to_string(),
                Err(e) => format!("Transfer: {}", short_error(e)),
            };
            tracing::info!(ok = result.is_ok(), "transfer requested");
            let _ = qt
                .queue(move |mut this| this.as_mut().set_status_text(QString::from(text.as_str())));
        });
    }

    pub fn send_dtmf(self: Pin<&mut Self>, key: &QString) {
        let Some(k) = key.to_string().chars().next() else {
            return;
        };
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let slot = call_slot().lock().await;
            let result = match (slot.active.as_ref(), slot.outgoing.as_ref()) {
                (Some(c), _) => c.send_dtmf(k),
                (None, Some(c)) => c.send_dtmf(k),
                _ => Err(anyhow::anyhow!("No call")),
            };
            drop(slot);
            if let Err(e) = result {
                let _ = qt.queue(move |mut this| {
                    this.as_mut().set_status_text(QString::from(
                        format!("Dial pad: {}", short_error(&e)).as_str(),
                    ));
                });
            }
        });
    }

    /// Apply roster changes and publish the roster to QML; in a meeting,
    /// ask for the cameras that are on (as Teams' gallery does, in the
    /// roster's order).
    fn apply_roster(mut self: Pin<&mut Self>, delta: Vec<teams_cli::calling::roster::Participant>) {
        // Someone who left ends their RTT line where it stood.
        let left: Vec<String> = delta.iter().filter(|p| !p.active).map(|p| p.id.clone()).collect();
        let mut ended = Vec::new();
        for id in &left {
            ended.extend(self.as_mut().rust_mut().rtt_lines.end_user(id));
        }
        self.as_mut().show_rtt(ended);
        let mut roster = std::mem::take(&mut self.as_mut().rust_mut().roster);
        teams_cli::calling::roster::apply(&mut roster, delta);

        let json = serde_json::to_string(&roster).unwrap_or_else(|_| "[]".into());
        let me = self.rust().user_mri.to_string().to_ascii_lowercase();
        let off = self.rust().incoming_video_off;
        let widths = self.rust().video_widths.clone();
        let cameras: Vec<(String, i64, u32)> = roster
            .iter()
            .filter(|p| p.id != me && !off)
            .filter_map(|p| {
                let w = widths.get(&p.id).copied().unwrap_or(1280.0).round() as u32;
                p.video_source.map(|s| (p.id.clone(), s, w))
            })
            .collect();
        // The presenter: whoever else shares their screen.
        let presenter = roster
            .iter()
            .find(|p| p.id != me && p.share_source.is_some())
            .map(|p| (p.id.clone(), p.share_source));
        let share_mri = presenter.as_ref().map(|p| p.0.clone()).unwrap_or_default();
        if self.rust().call_share_mri.to_string() != share_mri {
            self.as_mut()
                .set_call_share_mri(QString::from(share_mri.as_str()));
        }
        let share_source = presenter.and_then(|p| p.1);
        // The attendance list: who else is here now.
        if self.rust().call_meeting && !roster.is_empty() {
            let here: Vec<(String, String)> = roster
                .iter()
                .filter(|p| p.id != me && p.active)
                .map(|p| (p.id.clone(), p.name.clone()))
                .collect();
            let (mri, name) = (self.rust().user_mri.to_string(), self.rust().user_name.to_string());
            self.as_mut()
                .rust_mut()
                .attendance
                .update((&mri, &name), &here, chrono::Local::now());
        }
        self.as_mut().rust_mut().roster = roster;
        self.as_mut()
            .set_call_roster_json(QString::from(json.as_str()));
        // The recording indicator names its starters from the roster.
        if !self.rust().processing.indicator_state().is_empty() {
            self.as_mut().show_recording_indicator();
        }
        if self.rust().call_meeting {
            let qt = self.qt_thread();
            runtime().spawn(async move {
                let sources: Vec<(i64, u32)> = cameras.iter().map(|c| (c.1, c.2)).collect();
                let shown = match call_slot().lock().await.outgoing.as_ref() {
                    Some(call) => {
                        call.show_share(share_source);
                        call.show_videos(&sources)
                    }
                    None => return,
                };
                let keys: serde_json::Map<String, serde_json::Value> = cameras
                    .iter()
                    .filter_map(|(mri, src, _)| Some((mri.clone(), shown.get(src)?.clone().into())))
                    .collect();
                let json = serde_json::Value::Object(keys).to_string();
                let _ = qt.queue(move |mut this| {
                    if this.rust().call_video_json.to_string() != json {
                        tracing::info!(videos = %json, "meeting videos");
                        this.as_mut()
                            .set_call_video_json(QString::from(json.as_str()));
                    }
                });
            });
        }
    }

    /// Show the call as over; the UI fades it out from "ended".
    fn end_call_ui(mut self: Pin<&mut Self>) {
        self.as_mut().set_call_held(false);
        self.as_mut().set_call_held_by_peer(false);
        self.as_mut().set_call_can_dtmf(false);
        self.as_mut().set_call_hand_raised(false);
        if !self.rust().call_state.is_empty() {
            self.as_mut().set_call_state(QString::from("ended"));
        }
        self.as_mut().set_call_camera_on(false);
        self.as_mut().set_call_network_strength(QString::from("Good"));
        self.as_mut().set_call_can_video(false);
        self.as_mut().set_call_can_share(false);
        self.as_mut().set_call_sharing(false);
    }

    /// Poll the presence of 1:1 chat partners every minute (Teams shows a
    /// badge on each avatar).
    fn start_presence(self: Pin<&mut Self>) {
        static STARTED: AtomicBool = AtomicBool::new(false);
        if STARTED.swap(true, Ordering::SeqCst) {
            return;
        }
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let http = reqwest::Client::new();
            loop {
                let (tx, rx) = tokio::sync::oneshot::channel::<Vec<String>>();
                let _ = qt.queue(move |this| {
                    let mut mris: Vec<String> = this
                        .rust()
                        .chats
                        .iter()
                        .filter_map(|c| c["peerMri"].as_str().map(str::to_string))
                        .collect();
                    // Yours too (your status message).
                    if let Some(me) = this.rust().my_mri.clone()
                        && !mris.iter().any(|m| m.eq_ignore_ascii_case(&me))
                    {
                        mris.push(me);
                    }
                    let _ = tx.send(mris);
                });
                let mris = rx.await.unwrap_or_default();
                match teams_cli::api::presence::get_presences(&http, &mris).await {
                    Ok(list) => {
                        let _ = qt.queue(move |mut this| {
                            let me = this.rust().my_mri.clone().unwrap_or_default();
                            for p in list {
                                if p.mri.eq_ignore_ascii_case(&me) {
                                    let note = json!({ "text": p.note_text, "html": p.note_html, "pinned": p.note_pinned, "expiry": p.note_expiry }).to_string();
                                    if this.rust().my_note_json.to_string() != note {
                                        this.as_mut().set_my_note_json(QString::from(note.as_str()));
                                    }
                                    if this.rust().my_status_ends.to_string() != p.forced_until {
                                        this.as_mut().set_my_status_ends(QString::from(p.forced_until.as_str()));
                                    }
                                    if this.rust().my_work_location.to_string() != p.work_location {
                                        this.as_mut().set_my_work_location(QString::from(p.work_location.as_str()));
                                    }
                                }
                                let note = json!({ "text": p.note_text, "html": p.note_html, "pinned": p.note_pinned, "ooo": p.out_of_office });
                                this.as_mut().rust_mut().peer_notes.insert(p.mri.clone(), note);
                                this.as_mut()
                                    .rust_mut()
                                    .presence
                                    .insert(p.mri, p.availability);
                            }
                            this.as_mut().publish_chats();
                        });
                    }
                    Err(e) => tracing::warn!("presence lookup failed: {}", short_error(&e)),
                }
                tokio::time::sleep(std::time::Duration::from_secs(60)).await;
            }
        });
    }

    /// Teams' chat bubble: someone else's message in the chat of the call
    /// we're in, unless bubbles are off for this call.
    fn maybe_chat_bubble(self: Pin<&mut Self>, m: &teams_cli::event_hub::PushedMessage) {
        let in_call = self.rust().call_state.to_string() == "connected";
        let thread = self.rust().call_thread_id.to_string();
        if !in_call || thread.is_empty() || m.conversation_id != thread || self.rust().call_chat_bubbles_suppressed {
            return;
        }
        let mine = self.rust().my_mri.as_deref().is_some_and(|me| me.eq_ignore_ascii_case(&m.sender_mri))
            || (!m.sender_name.is_empty() && m.sender_name == self.rust().user_name.to_string());
        if mine || m.text.trim().is_empty() {
            return;
        }
        // Teams previews the first 200 characters.
        let text: String = m.text.chars().take(200).collect();
        self.chat_bubble(
            QString::from(m.sender_mri.as_str()),
            QString::from(m.sender_name.as_str()),
            QString::from(text.as_str()),
        );
    }

    /// Show a desktop notification for someone else's message, unless its
    /// chat is open in the focused window.
    fn maybe_notify(
        mut self: Pin<&mut Self>,
        m: teams_cli::event_hub::PushedMessage,
        qt: cxx_qt::CxxQtThread<qobject::Backend>,
    ) {
        let own = self.rust().user_name.to_string();
        let mine = (!m.sender_name.is_empty() && m.sender_name == own)
            || self
                .rust()
                .my_mri
                .as_deref()
                .is_some_and(|me| me.eq_ignore_ascii_case(&m.sender_mri));
        let open = self.rust().window_active
            && m.conversation_id == self.rust().current_chat_id.to_string();
        // Settings ▸ Notifications and activity, as Teams applies it.
        let prefs = notify_prefs(&self.rust().settings_json.to_string(), &load_settings());
        // Muted for this call (More ▸ Settings ▸ Mute notifications), or
        // notifications off during calls and meetings.
        let in_call = ["connected", "connecting", "calling"].contains(&self.rust().call_state.to_string().as_str());
        let banners_on = (!prefs.mute_all || (m.urgent && prefs.allow_urgent_when_muted))
            && !(in_call && (self.rust().call_notifications_muted || !prefs.during_calls));
        let mentioned = self
            .rust()
            .my_mri
            .as_deref()
            .is_some_and(|me| m.mentions.iter().any(|x| x.eq_ignore_ascii_case(me)));
        let channel = m.conversation_id.ends_with("@thread.tacv2");
        let muted = chat_muted(&self.rust().chats, &m.conversation_id);
        // A personal @mention banners unless that's off; a chat message
        // banners when chat banners are on; channel posts and muted chats
        // only for mentions.
        let mention_banner = mentioned && prefs.personal_mention_banners;
        if !should_notify(
            mine,
            open,
            m.text.is_empty(),
            banners_on,
            !prefs.chat_banners,
            channel || muted,
            mention_banner,
        ) {
            return;
        }
        // Your presence decides, as in Teams.
        let availability = self
            .rust()
            .my_mri
            .as_deref()
            .and_then(|me| self.rust().presence.get(me).cloned())
            .unwrap_or_default();
        let presenting = teams_cli::api::presence::changes().borrow().call
            == teams_cli::api::presence::CallState::Presenting;
        let decision = toast_decision(&availability, presenting, m.urgent);
        if decision == Toast::Drop {
            return;
        }
        let chat_name = if channel {
            self.channel_label(&m.conversation_id)
        } else {
            self.rust()
                .chats
                .iter()
                .find(|c| c["id"].as_str() == Some(m.conversation_id.as_str()))
                .and_then(|c| c["name"].as_str().map(str::to_string))
                .unwrap_or_default()
        };
        // Teams: "<name> mentioned you" for mentions, else the sender.
        let title = match (m.sender_name.is_empty(), mentioned) {
            (false, true) => format!("{} mentioned you", m.sender_name),
            (false, false) => m.sender_name.clone(),
            (true, _) => chat_name.clone(),
        };
        // Previews off: Teams' "Message preview hidden".
        let text: String = if prefs.previews {
            m.text.chars().take(NOTIFICATION_BODY_CHARS).collect()
        } else {
            "Message preview hidden".to_string()
        };
        // Where it was said, for channels and named chats.
        let body = if channel && !chat_name.is_empty() {
            format!("{chat_name}\n{text}")
        } else {
            text
        };
        let (title, body) = if decision == Toast::Redacted {
            ("You have a new notification".to_string(), String::new())
        } else {
            (title, body)
        };
        let chat_id = m.conversation_id.clone();
        let busy = matches!(availability.as_str(), "Busy" | "DoNotDisturb" | "InACall" | "InAMeeting") || in_call;
        let silent = !prefs.sound || (busy && !prefs.sound_when_busy);
        let timeout = prefs.seconds * 1000;
        if prefs.flash {
            self.as_mut().flash_requested();
        }
        std::thread::spawn(move || {
            let shown = notify_rust::Notification::new()
                .appname("OST")
                .summary(&title)
                .body(&body)
                .icon("ost-desktop")
                .action("default", "Open")
                .hint(notify_rust::Hint::Category("im.received".into()))
                .hint(notify_rust::Hint::SuppressSound(silent))
                .timeout(notify_rust::Timeout::Milliseconds(timeout))
                .show();
            match shown {
                Ok(handle) => handle.wait_for_action(|action| {
                    if action == "default" {
                        let _ = qt.queue(move |mut this| {
                            this.as_mut().select_chat(
                                &QString::from(chat_id.as_str()),
                                &QString::from(chat_name.as_str()),
                            );
                            this.as_mut().activate_requested();
                        });
                    }
                }),
                Err(e) => tracing::warn!("notification failed: {e}"),
            }
        });
    }

    /// Teams' toast for Meet now started in a chat (527114 `uMe`): the chat's
    /// name (or "(No title)"), "{name} started a meeting", Join and Message.
    /// As Teams does, once per call, not for muted chats nor when we're
    /// already in that chat's call, and by the same banner and presence
    /// rules as messages. The
    /// chat list reloads too: its liveness entry has changed.
    fn notify_meeting_start(
        mut self: Pin<&mut Self>,
        start: teams_cli::calling::incoming::MeetingStart,
        qt: cxx_qt::CxxQtThread<qobject::Backend>,
    ) {
        static SHOWN: OnceLock<std::sync::Mutex<std::collections::HashSet<String>>> =
            OnceLock::new();
        self.as_mut().reload_chats();
        let first = SHOWN
            .get_or_init(Default::default)
            .lock()
            .map(|mut s| s.insert(start.call_id.clone()))
            .unwrap_or(false);
        let mine = self
            .rust()
            .my_mri
            .as_deref()
            .is_some_and(|me| me.eq_ignore_ascii_case(&start.initiator));
        let in_it = !self.rust().call_state.is_empty()
            && self.rust().call_thread_id.to_string() == start.thread_id;
        // Settings ▸ Notifications ▸ Meet now start notifications (off by
        // default, as in Teams), unless everything is muted.
        let prefs = notify_prefs(&self.rust().settings_json.to_string(), &load_settings());
        let banners_on = prefs.meet_now && !prefs.mute_all;
        let muted = chat_muted(&self.rust().chats, &start.thread_id);
        if !first || mine || in_it || !banners_on || muted {
            return;
        }
        let availability = self
            .rust()
            .my_mri
            .as_deref()
            .and_then(|me| self.rust().presence.get(me).cloned())
            .unwrap_or_default();
        let presenting = teams_cli::api::presence::changes().borrow().call
            == teams_cli::api::presence::CallState::Presenting;
        let decision = toast_decision(&availability, presenting, false);
        if decision == Toast::Drop {
            return;
        }
        let chat_name = self
            .rust()
            .chats
            .iter()
            .find(|c| c["id"].as_str() == Some(start.thread_id.as_str()))
            .and_then(|c| c["name"].as_str().map(str::to_string))
            .filter(|n| !n.is_empty())
            .unwrap_or_else(|| "(No title)".to_string());
        let who = if start.initiator_name.is_empty() {
            "Someone".to_string()
        } else {
            start.initiator_name.clone()
        };
        let (title, body) = if decision == Toast::Redacted {
            ("You have a new notification".to_string(), String::new())
        } else {
            (chat_name.clone(), format!("{who} started a meeting"))
        };
        let chat_id = start.thread_id.clone();
        std::thread::spawn(move || {
            let shown = notify_rust::Notification::new()
                .appname("OST")
                .summary(&title)
                .body(&body)
                .icon("ost-desktop")
                .action("join", "Join")
                .action("message", "Message")
                .action("default", "Open")
                .hint(notify_rust::Hint::Category("call".into()))
                .show();
            match shown {
                Ok(handle) => handle.wait_for_action(|action| {
                    let join = action == "join";
                    if join || action == "message" || action == "default" {
                        let _ = qt.queue(move |mut this| {
                            this.as_mut().select_chat(
                                &QString::from(chat_id.as_str()),
                                &QString::from(chat_name.as_str()),
                            );
                            this.as_mut().activate_requested();
                            if join {
                                this.as_mut().join_group_call();
                            }
                        });
                    }
                }),
                Err(e) => tracing::warn!("notification failed: {e}"),
            }
        });
    }

    /// "Team > Channel" for a channel id, from the teams list.
    fn channel_label(&self, id: &str) -> String {
        let teams: serde_json::Value =
            serde_json::from_str(&self.rust().teams_json.to_string()).unwrap_or_default();
        teams
            .as_array()
            .into_iter()
            .flatten()
            .find_map(|t| {
                let ch = t["channels"].as_array()?.iter().find(|c| c["id"] == id)?;
                Some(format!(
                    "{} > {}",
                    t["name"].as_str().unwrap_or_default(),
                    ch["name"].as_str().unwrap_or_default()
                ))
            })
            .unwrap_or_default()
    }

    fn on_typing(mut self: Pin<&mut Self>, t: teams_cli::event_hub::Typing) {
        tracing::info!(
            stopped = t.stopped,
            named = !t.sender_name.is_empty(),
            "typing event"
        );
        let chat = self.rust().current_chat_id.to_string();
        let mine = self
            .rust()
            .my_mri
            .as_deref()
            .is_some_and(|me| me.eq_ignore_ascii_case(&t.sender_mri))
            || (t.sender_mri.is_empty() && t.sender_name == self.rust().user_name.to_string());
        // Teams shows no typing indicator in channels, nor in chats above
        // its roster limit.
        if t.conversation_id != chat
            || mine
            || chat.ends_with("@thread.tacv2")
            || api::messages::roster_size(&chat).is_some_and(|n| n > api::messages::MAX_ROSTER)
        {
            return;
        }
        let key = if t.sender_mri.is_empty() {
            t.sender_name.clone()
        } else {
            t.sender_mri.to_ascii_lowercase()
        };
        // The name: the event's, else the person's (Teams resolves it from
        // the MRI); looked up first if not yet known.
        let name = if !t.sender_name.is_empty() {
            Some(t.sender_name.clone())
        } else {
            api::messages::cached_name(&t.sender_mri)
        };
        let Some(name) = name else {
            if t.stopped || t.sender_mri.is_empty() {
                return;
            }
            let qt = self.qt_thread();
            let one_on_one = chat.ends_with("@unq.gbl.spaces");
            let fallback = self.rust().current_chat_name.to_string();
            runtime().spawn(async move {
                let found = match TeamsClient::new().await {
                    Ok(client) => api::messages::person_name(&client, &t.sender_mri).await,
                    Err(_) => None,
                };
                // A 1:1 chat's other member is the one the chat is named after.
                let Some(name) = found.or_else(|| one_on_one.then_some(fallback)) else {
                    return;
                };
                let _ = qt.queue(move |mut this| {
                    this.as_mut().on_typing(teams_cli::event_hub::Typing {
                        sender_name: name,
                        ..t
                    })
                });
            });
            return;
        };
        let now = std::time::Instant::now();
        let typers = &mut self.as_mut().rust_mut().typers;
        typers.retain(|x| x.key != key && x.until > now);
        if !t.stopped {
            typers.push(Typer {
                key,
                name,
                until: now + std::time::Duration::from_secs(TYPING_TTL_SECS),
            });
        }
        self.as_mut().refresh_typing();
    }

    /// A message from someone typing ends their typing (Teams: any other
    /// message from that user removes them); the others stay.
    fn typer_posted(mut self: Pin<&mut Self>, m: &teams_cli::event_hub::PushedMessage) {
        if m.conversation_id != self.rust().current_chat_id.to_string() {
            return;
        }
        let mri = m.sender_mri.to_ascii_lowercase();
        let before = self.rust().typers.len();
        self.as_mut()
            .rust_mut()
            .typers
            .retain(|x| x.key != mri && x.key != m.sender_name);
        if self.rust().typers.len() != before {
            self.as_mut().refresh_typing();
        }
    }

    /// Show who is typing, as Teams words it; when the last typer leaves,
    /// the line stays 3 s more. Expired typers drop off on their own.
    fn refresh_typing(mut self: Pin<&mut Self>) {
        let now = std::time::Instant::now();
        self.as_mut().rust_mut().typers.retain(|x| x.until > now);
        let names: Vec<String> = self.rust().typers.iter().map(|x| x.name.clone()).collect();
        let generation = self.rust().typing_generation + 1;
        self.as_mut().rust_mut().typing_generation = generation;
        let qt = self.qt_thread();
        if names.is_empty() {
            runtime().spawn(async move {
                tokio::time::sleep(std::time::Duration::from_millis(3000)).await;
                let _ = qt.queue(move |mut this| {
                    if this.rust().typing_generation == generation {
                        this.as_mut().set_typing_text(QString::default());
                        this.as_mut().set_typing_avatar(QString::default());
                        this.as_mut().set_typing_avatar_id(QString::default());
                    }
                });
            });
            return;
        }
        let text = typing_text(&names);
        if let Some(latest) = self.rust().typers.last().cloned() {
            let id = latest.key.strip_prefix("8:orgid:").unwrap_or_default();
            self.as_mut().set_typing_avatar_id(QString::from(id));
            self.as_mut()
                .set_typing_avatar(QString::from(latest.name.as_str()));
        }
        self.as_mut().set_typing_text(QString::from(text.as_str()));
        // Wake when the next typer expires.
        let next = self
            .rust()
            .typers
            .iter()
            .map(|x| x.until)
            .min()
            .unwrap_or(now);
        runtime().spawn(async move {
            tokio::time::sleep(next.saturating_duration_since(std::time::Instant::now())).await;
            let _ = qt.queue(move |mut this| {
                if this.rust().typing_generation == generation {
                    this.as_mut().refresh_typing();
                }
            });
        });
    }

    /// Reload the calendar range last shown (after scheduling something).
    fn refresh_calendar(mut self: Pin<&mut Self>) {
        if let Some((a, b)) = self.rust().calendar_range.clone() {
            self.as_mut()
                .load_calendar(&QString::from(a.as_str()), &QString::from(b.as_str()));
        }
    }

    pub fn load_calendar(mut self: Pin<&mut Self>, start_utc: &QString, end_utc: &QString) {
        let (start, end) = (start_utc.to_string(), end_utc.to_string());
        self.as_mut().rust_mut().calendar_range = Some((start.clone(), end.clone()));
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                api::calendar::calendar_view(&client, &start, &end).await
            }
            .await;
            match result {
                Ok(events) => {
                    tracing::info!(events = events.len(), "calendar loaded");
                    let text = serde_json::to_string(&events).unwrap_or_else(|_| "[]".into());
                    let _ = qt.queue(move |mut this| {
                        this.as_mut()
                            .set_calendar_json(QString::from(text.as_str()))
                    });
                }
                Err(e) => tracing::warn!("calendar failed: {}", short_error(&e)),
            }
        });
    }

    pub fn search_people(self: Pin<&mut Self>, query: &QString) {
        self.search_people_impl(query, false)
    }

    pub fn search_people_with_me(self: Pin<&mut Self>, query: &QString) {
        self.search_people_impl(query, true)
    }

    fn search_people_impl(mut self: Pin<&mut Self>, query: &QString, include_me: bool) {
        let q = query.to_string();
        let generation = self.rust().people_query_generation + 1;
        self.as_mut().rust_mut().people_query_generation = generation;
        if q.trim().len() < 2 {
            self.as_mut().set_people_json(QString::from("[]"));
            return;
        }
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                api::directory::search_directory(&client, &q, include_me).await
            }
            .await;
            let _ = qt.queue(move |mut this| {
                // A newer query has been typed since.
                if this.rust().people_query_generation != generation {
                    return;
                }
                match result {
                    Ok(people) => {
                        let text = serde_json::to_string(&people).unwrap_or_else(|_| "[]".into());
                        this.as_mut().set_people_json(QString::from(text.as_str()));
                    }
                    Err(e) => tracing::warn!("people search failed: {}", short_error(&e)),
                }
            });
        });
    }

    pub fn open_chat_with(self: Pin<&mut Self>, oid: &QString, name: &QString) {
        let Some(me) = teams_cli::config::Config::load()
            .ok()
            .and_then(|c| c.object_id())
        else {
            return;
        };
        let id = api::directory::one_on_one_chat_id(&me, &oid.to_string());
        self.select_chat(&QString::from(id.as_str()), name);
    }

    pub fn load_calls(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                let mut calls = api::call_history(&client, CALL_HISTORY_LIMIT).await?;
                // Calls OST placed carry no display name for the other
                // side; look those people up once each.
                let mut names: HashMap<String, String> = HashMap::new();
                for c in calls.iter().filter(|c| !c.peer_name.is_empty()) {
                    names
                        .entry(c.peer_mri.clone())
                        .or_insert_with(|| c.peer_name.clone());
                }
                for c in calls.iter_mut().filter(|c| c.peer_name.is_empty()) {
                    if let Some(n) = names.get(&c.peer_mri) {
                        c.peer_name = n.clone();
                        continue;
                    }
                    let Some(oid) = c
                        .peer_mri
                        .strip_prefix("8:orgid:")
                        .filter(|o| o.chars().all(|ch| ch.is_ascii_hexdigit() || ch == '-'))
                    else {
                        continue;
                    };
                    if let Ok(r) = client
                        .graph_get(&format!("/users/{oid}?$select=displayName"))
                        .await
                    {
                        let v: serde_json::Value = r.json().await.unwrap_or_default();
                        if let Some(n) = v["displayName"].as_str() {
                            names.insert(c.peer_mri.clone(), n.to_string());
                            c.peer_name = n.to_string();
                        }
                    }
                }
                anyhow::Ok(calls)
            }
            .await;
            match result {
                Ok(calls) => {
                    let text = serde_json::to_string(&calls).unwrap_or_else(|_| "[]".into());
                    let _ = qt.queue(move |mut this| {
                        this.as_mut().set_calls_json(QString::from(text.as_str()))
                    });
                }
                Err(e) => tracing::warn!("call history failed: {}", short_error(&e)),
            }
        });
    }

    pub fn edit_message(self: Pin<&mut Self>, message_id: &QString, text: &QString) {
        let (id, text) = (message_id.to_string(), text.to_string());
        if text.trim().is_empty() {
            return;
        }
        let at = id.clone();
        self.message_action(&at, move |client, chat| {
            Box::pin(async move { api::messages::edit_message(&client, &chat, &id, &text).await })
        });
    }

    pub fn set_thread_read(self: Pin<&mut Self>, root_id: &QString, change: &QString, newest_reply: &QString) {
        use api::msgactions::HorizonChange;
        let id = root_id.to_string();
        let newest = newest_reply.to_string().parse::<i64>().unwrap_or(0);
        let change = match (change.to_string().as_str(), newest) {
            ("clear", _) => HorizonChange::ClearBookmark,
            ("read", n) if n > 0 => HorizonChange::ReadTo(n),
            ("unread", n) if n > 0 => HorizonChange::UnreadFrom(n),
            _ => return,
        };
        let at = id.clone();
        self.message_action(&at, move |client, chat| {
            Box::pin(async move { api::msgactions::set_thread_horizon(&client, &chat, &id, change).await })
        });
    }

    pub fn set_thread_following(self: Pin<&mut Self>, root_id: &QString, follow: bool) {
        let id = root_id.to_string();
        let at = id.clone();
        self.message_action(&at, move |client, chat| {
            Box::pin(
                async move { api::msgactions::set_following(&client, &chat, &id, follow).await },
            )
        });
    }

    pub fn edit_message_rich(
        self: Pin<&mut Self>,
        message_id: &QString,
        editor_html: &QString,
        quote_json: &QString,
        media_json: &QString,
    ) {
        let id = message_id.to_string();
        // The emoticons, custom emoji and pictures in the box go out in
        // Teams' own form (the edit form gave them back; the picker adds).
        let media: Vec<api::messages::ComposeMedia> =
            serde_json::from_str(&media_json.to_string()).unwrap_or_default();
        let (html, mentions) =
            api::messages::teams_html_with_media(&editor_html.to_string(), &media);
        if html.trim().is_empty() {
            return;
        }
        let quote: Option<api::messages::Quote> =
            serde_json::from_str(&quote_json.to_string()).ok();
        let at = id.clone();
        self.message_action(&at, move |client, chat| {
            Box::pin(async move {
                api::messages::edit_message_html(
                    &client,
                    &chat,
                    &id,
                    &html,
                    quote.as_ref(),
                    Some(&mentions),
                )
                .await
            })
        });
    }

    pub fn delete_message(self: Pin<&mut Self>, message_id: &QString) {
        let id = message_id.to_string();
        deleted_here().lock().unwrap().insert(id.clone());
        let at = id.clone();
        self.message_action(&at, move |client, chat| {
            Box::pin(async move { api::messages::delete_message(&client, &chat, &id).await })
        });
    }

    /// Undo a delete made in this session (Teams' Undo on the tombstone).
    pub fn undo_delete_message(self: Pin<&mut Self>, message_id: &QString) {
        let id = message_id.to_string();
        deleted_here().lock().unwrap().remove(&id);
        let at = id.clone();
        self.message_action(&at, move |client, chat| {
            Box::pin(async move { api::messages::undelete_message(&client, &chat, &id).await })
        });
    }

    /// Run a message change in the open chat, then reload it.
    fn message_action<F>(self: Pin<&mut Self>, message_id: &str, act: F)
    where
        F: FnOnce(
                TeamsClient,
                String,
            ) -> std::pin::Pin<
                Box<dyn std::future::Future<Output = anyhow::Result<()>> + Send>,
            > + Send
            + 'static,
    {
        let chat_id = self.chat_of(message_id);
        if chat_id.is_empty() {
            return;
        }
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let changed = chat_id.clone();
            let result = match TeamsClient::new().await {
                Ok(client) => act(client, chat_id).await,
                Err(e) => Err(e),
            };
            let _ = qt.queue(move |mut this| match result {
                Ok(()) => this.as_mut().reload_where(&changed),
                Err(e) => this
                    .as_mut()
                    .set_status_text(QString::from(short_error(&e).as_str())),
            });
        });
    }

    pub fn toggle_reaction(self: Pin<&mut Self>, message_id: &QString, key: &QString, on: bool) {
        let (message_id, key) = (message_id.to_string(), key.to_string());
        let chat_id = self.chat_of(&message_id);
        if chat_id.is_empty() || message_id.is_empty() {
            return;
        }
        // Adding another skin tone of an emoticon we reacted with replaces
        // that one (Teams: one tone per emoticon).
        let replaces: Option<String> = on
            .then(|| {
                let shown: serde_json::Value = serde_json::from_str(&self.shown_json_of(&chat_id)).ok()?;
                let common = api::messages::common_key(&key);
                let m = shown
                    .as_array()?
                    .iter()
                    .find(|m| m["id"].as_str() == Some(message_id.as_str()))?;
                m["reactions"]
                    .as_array()?
                    .iter()
                    .find(|r| {
                        r["mine"].as_bool() == Some(true)
                            && r["key"].as_str() == Some(common)
                            && r["my_key"].as_str() != Some(key.as_str())
                    })
                    .and_then(|r| r["my_key"].as_str().map(str::to_string))
            })
            .flatten();
        // Adding one moves it to the front of Recent, which roams (Teams'
        // addEmojisInRecent).
        let recent = on.then(|| {
            let now: Vec<String> =
                serde_json::from_str(&self.rust().recent_reactions_json.to_string())
                    .unwrap_or_default();
            api::emoticons::note_recent(&now, &key)
        });
        let mut this = self;
        if let Some(r) = &recent {
            let text = serde_json::to_string(r).unwrap_or_default();
            this.as_mut()
                .set_recent_reactions_json(QString::from(text.as_str()));
        }
        let qt = this.qt_thread();
        let changed = chat_id.clone();
        runtime().spawn(async move {
            // One reaction write at a time: the service rejects concurrent
            // changes to a message's emotions.
            static WRITES: std::sync::OnceLock<tokio::sync::Mutex<()>> = std::sync::OnceLock::new();
            let _turn = WRITES.get_or_init(Default::default).lock().await;
            let result = async {
                let client = TeamsClient::new().await?;
                if let Some(old) = &replaces {
                    let wire = api::emoticons::server_key(old);
                    api::messages::set_reaction(&client, &chat_id, &message_id, wire, false)
                        .await?;
                }
                // The service keys a few emoticons differently (Teams' 77708).
                let wire = api::emoticons::server_key(&key);
                api::messages::set_reaction(&client, &chat_id, &message_id, wire, on).await?;
                if let Some(r) = recent
                    && let Err(e) = api::emoticons::set_recent_reactions(&client, &r).await
                {
                    tracing::warn!("recent reactions not saved: {}", short_error(&e));
                }
                anyhow::Ok(())
            }
            .await;
            let _ = qt.queue(move |mut this| match result {
                Ok(()) => this.as_mut().reload_where(&changed),
                Err(e) => {
                    tracing::warn!("reaction not changed: {}", short_error(&e));
                    // A message at the service's size limit takes no more
                    // reactions (413); Teams' words for it.
                    let text = if format!("{e:#}").contains("HTTP 413") {
                        "Current message size limit reached. We can't add any more reactions.".to_string()
                    } else {
                        short_error(&e)
                    };
                    this.as_mut().set_status_text(QString::from(text.as_str()));
                }
            });
        });
    }

    pub fn set_ringer(self: Pin<&mut Self>, on: bool) {
        static RINGER: std::sync::Mutex<Option<teams_cli::calling::ringtone::Ringtone>> =
            std::sync::Mutex::new(None);
        let mut ringer = RINGER.lock().unwrap_or_else(|e| e.into_inner());
        match (on, ringer.is_some()) {
            (true, false) => {
                *ringer = teams_cli::calling::ringtone::Ringtone::start();
                tracing::info!(playing = ringer.is_some(), "ringing");
            }
            (false, true) => *ringer = None,
            _ => {}
        }
    }

    pub fn user_typing(mut self: Pin<&mut Self>) {
        let chat_id = self.rust().current_chat_id.to_string();
        if chat_id.is_empty() {
            return;
        }
        let now = std::time::Instant::now();
        if self
            .rust()
            .last_typing_sent
            .is_some_and(|t| now.duration_since(t).as_secs() < TYPING_SEND_INTERVAL_SECS)
        {
            return;
        }
        self.as_mut().rust_mut().last_typing_sent = Some(now);
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                api::send_typing(&client, &chat_id).await
            }
            .await;
            if let Err(e) = result {
                tracing::debug!("typing indicator failed: {}", short_error(&e));
            }
        });
    }

    fn on_chat_push(mut self: Pin<&mut Self>, ids: Vec<String>) {
        // Waiting in a lobby whose chat already exists: the first push of
        // the lobby chat thread is how its messages reach us (no
        // conversationUpdate then); a meeting thread that is the lobby's
        // chat (meetingChatType "lobby") becomes the call's lobby chat.
        if self.rust().call_state.to_string() == "lobby" && self.rust().call_lobby_thread.is_empty() {
            let main = self.rust().call_thread_id.to_string();
            let candidates: Vec<String> = ids.iter().filter(|i| i.starts_with("19:meeting_") && **i != main).cloned().collect();
            if !candidates.is_empty() {
                let qt = self.qt_thread();
                runtime().spawn(async move {
                    let Ok(client) = TeamsClient::new().await else { return };
                    for id in candidates {
                        let url = format!("{}/v1/threads/{}?view=msnp24Equivalent", client.chat_service_url(), id);
                        let Ok(resp) = client.chat_get(&url).await else { continue };
                        let Ok(v) = resp.json::<serde_json::Value>().await else { continue };
                        if v.pointer("/properties/meetingChatType").and_then(|t| t.as_str()) == Some("lobby") {
                            tracing::info!("lobby chat thread from a chat push");
                            let _ = qt.queue(move |mut this| {
                                if this.rust().call_lobby_thread.is_empty() {
                                    this.as_mut().set_call_lobby_thread(QString::from(id.as_str()));
                                }
                            });
                            break;
                        }
                    }
                });
            }
        }
        let current = self.rust().current_chat_id.to_string();
        let mut list_changed = false;
        // New notifications: refresh Activity (and its badge).
        if ids.iter().any(|i| i == "48:notifications") {
            self.as_mut().load_activity();
        }
        for id in ids.iter().filter(|i| !i.starts_with("48:")) {
            let channel = id.split(';').next().unwrap_or_default().to_string();
            let open: Vec<String> = self
                .rust()
                .thread_windows
                .iter()
                .filter(|t| window_channel(t) == channel.as_str())
                .cloned()
                .collect();
            for t in open {
                self.as_mut().reload_thread_window(t);
            }
        }
        let mut reload = false;
        for id in ids.into_iter().filter(|i| !i.starts_with("48:")) {
            // A thread's push names "<channel>;messageid=<post>": the open
            // channel shows its replies (and, in the Threads layout, their
            // counts and replies also sent to the channel).
            if id == current || id.split(';').next() == Some(current.as_str()) {
                reload = true;
            } else {
                list_changed |= self.as_mut().rust_mut().unread.insert(id);
            }
        }
        if reload {
            self.as_mut().reload_messages();
        }
        if list_changed {
            self.as_mut().publish_chats();
        }
        self.as_mut().reload_chats();
    }

    /// Reload the chat list quietly (new chats, new order), keeping unread
    /// flags. Pushes arriving while a reload runs are folded into it.
    fn reload_chats(self: Pin<&mut Self>) {
        static RUNNING: AtomicBool = AtomicBool::new(false);
        static AGAIN: AtomicBool = AtomicBool::new(false);
        if RUNNING.swap(true, Ordering::SeqCst) {
            AGAIN.store(true, Ordering::SeqCst);
            return;
        }
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = load_overview().await;
            let _ = qt.queue(move |mut this| {
                RUNNING.store(false, Ordering::SeqCst);
                match result {
                    Ok((_, chats)) => {
                        this.as_mut().rust_mut().chats = chats;
                        this.as_mut().publish_chats();
                    }
                    Err(e) => tracing::warn!("chat list reload failed: {}", short_error(&e)),
                }
                if AGAIN.swap(false, Ordering::SeqCst) {
                    this.as_mut().reload_chats();
                }
            });
        });
    }

    pub fn refresh(mut self: Pin<&mut Self>) {
        self.as_mut().set_busy(true);
        self.as_mut().set_status_text(QString::from("Loading…"));
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = load_overview().await;
            tracing::info!(ok = result.is_ok(), "overview loaded");
            if let Err(e) = &result {
                tracing::warn!("overview failed: {}", short_error(e));
            }
            let _ = qt.queue(move |mut this| {
                this.as_mut().set_busy(false);
                match result {
                    Ok((name, chats)) => {
                        this.as_mut().set_signed_in(true);
                        this.as_mut().set_user_name(QString::from(name.as_str()));
                        this.as_mut().load_profile();
                        this.as_mut().load_engagement();
                        this.as_mut().rust_mut().my_mri = teams_cli::config::Config::load()
                            .ok()
                            .and_then(|c| c.object_id())
                            .map(|oid| format!("8:orgid:{oid}").to_ascii_lowercase());
                        let mri = this.rust().my_mri.clone().unwrap_or_default();
                        this.as_mut().set_user_mri(QString::from(mri.as_str()));
                        this.as_mut().rust_mut().chats = chats;
                        this.as_mut().publish_chats();
                        this.as_mut().set_status_text(QString::default());
                        this.as_mut().start_push();
                        this.as_mut().start_presence();
                        this.as_mut().load_server_unread();
                        this.as_mut().load_teams();
                        this.as_mut().folders_load();
                        this.as_mut().load_activity();
                        // Teams' live settings (ECS), as Teams loads them
                        // at start.
                        runtime().spawn(async {
                            let r = async {
                                let client = TeamsClient::new().await?;
                                api::ecs::load(&client, &cache_base()).await
                            }
                            .await;
                            match r {
                                Ok(()) => tracing::info!(
                                    "ECS settings loaded (ring {})",
                                    api::ecs::segment("TeamsRing").unwrap_or_default()
                                ),
                                Err(e) => tracing::warn!("ECS settings: {}", short_error(&e)),
                            }
                        });
                    }
                    Err(e) => {
                        this.as_mut().set_signed_in(false);
                        this.as_mut()
                            .set_status_text(QString::from(short_error(&e).as_str()));
                    }
                }
            });
        });
    }

    pub fn select_chat(mut self: Pin<&mut Self>, chat_id: &QString, chat_name: &QString) {
        if self.as_mut().rust_mut().unread.remove(&chat_id.to_string()) {
            self.as_mut().publish_chats();
        }
        self.as_mut().rust_mut().typers.clear();
        self.as_mut().rust_mut().reply_quote = None;
        self.as_mut().rust_mut().next_importance.clear();
        self.as_mut().rust_mut().next_post = None;
        self.as_mut().rust_mut().next_schedule_ms = None;
        self.as_mut().rust_mut().typing_generation += 1;
        self.as_mut().set_typing_text(QString::default());
        self.as_mut().set_typing_avatar(QString::default());
        self.as_mut().set_typing_avatar_id(QString::default());
        self.as_mut().rust_mut().newest_message_id = None;
        read_at_open().lock().unwrap().remove(&chat_id.to_string());
        self.as_mut().set_current_chat_id(chat_id.clone());
        self.as_mut().set_current_chat_name(chat_name.clone());
        self.as_mut().set_messages_json(QString::from("[]"));
        self.as_mut().reload_messages();
        self.as_mut().load_chat_members();
        self.as_mut().load_chat_meeting();
        self.as_mut().load_scheduled();
        if chat_id.to_string().ends_with("@thread.tacv2") {
            self.as_mut().check_channel_layout(chat_id.to_string());
        }
    }

    /// A channel's layout as the chat service has it, when the teams list
    /// says otherwise (or nothing): Teams lays the channel out by it.
    fn check_channel_layout(self: Pin<&mut Self>, channel: String) {
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let Ok(client) = TeamsClient::new().await else { return };
            let Ok(Some(modality)) = api::messages::thread_modality(&client, &channel).await else { return };
            let _ = qt.queue(move |mut this| {
                let mut teams: serde_json::Value = serde_json::from_str(&this.rust().teams_json.to_string()).unwrap_or_default();
                let mut changed = false;
                for t in teams.as_array_mut().into_iter().flatten() {
                    for c in t["channels"].as_array_mut().into_iter().flatten() {
                        if c["id"].as_str() == Some(channel.as_str()) && c["layout"].as_str() != Some(modality.as_str()) {
                            c["layout"] = json!(modality);
                            changed = true;
                        }
                    }
                }
                this.as_mut().rust_mut().channel_layouts.insert(channel.clone(), modality.clone());
                if changed {
                    tracing::info!(%modality, "channel layout from the chat service");
                    this.as_mut().set_teams_json(QString::from(teams.to_string().as_str()));
                }
            });
        });
    }

    /// The open chat's scheduled messages (from your 48:drafts stream).
    fn load_scheduled(mut self: Pin<&mut Self>) {
        let chat_id = self.rust().current_chat_id.to_string();
        self.as_mut().set_scheduled_json(QString::from("[]"));
        if chat_id.is_empty() || chat_id.starts_with("48:") {
            return;
        }
        let me = self.rust().my_mri.clone().unwrap_or_default();
        let name = self.rust().user_name.to_string();
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                api::scheduled::list(&client, &me, &name).await
            }
            .await;
            let _ = qt.queue(move |mut this| {
                if this.rust().current_chat_id.to_string() != chat_id {
                    return;
                }
                match result {
                    Ok(list) => {
                        let mine: Vec<_> = list.into_iter().filter(|s| s.conversation == chat_id).collect();
                        let json = serde_json::to_string(&mine).unwrap_or_else(|_| "[]".into());
                        this.as_mut().set_scheduled_json(QString::from(json.as_str()));
                    }
                    Err(e) => tracing::debug!("scheduled messages unavailable: {}", short_error(&e)),
                }
            });
        });
    }

    pub fn set_next_schedule(mut self: Pin<&mut Self>, ms: &QString) {
        self.as_mut().rust_mut().next_schedule_ms = ms.to_string().parse::<i64>().ok().filter(|m| *m > 0);
    }

    pub fn find_in_chat(mut self: Pin<&mut Self>, key: &QString, thread: &QString, keywords: &QString, filters_json: &QString, from: i32) {
        let key = key.to_string();
        let thread = thread.to_string();
        let keywords = keywords.to_string().trim().to_string();
        let filters: api::find::Filters = serde_json::from_str(&filters_json.to_string()).unwrap_or_default();
        let from = from.max(0) as usize;
        // Earlier pages stay while the next one loads.
        let mut shown: serde_json::Value = serde_json::from_str(&self.rust().find_json.to_string()).unwrap_or_default();
        if from == 0 || shown["key"] != key.as_str() {
            shown = json!({ "key": key, "hits": [], "terms": [], "total": 0, "more": false });
        }
        shown["loading"] = true.into();
        shown["error"] = "".into();
        self.as_mut().rust_mut().find_key = key.clone();
        self.as_mut().set_find_json(QString::from(shown.to_string().as_str()));
        if thread.is_empty() || (keywords.is_empty() && filters.from_mail.is_empty() && filters.start.is_empty() && !filters.attachment && !filters.mentions) {
            shown["loading"] = false.into();
            self.as_mut().set_find_json(QString::from(shown.to_string().as_str()));
            return;
        }
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                let oid = client.object_id().unwrap_or_default();
                let tenant = client.tenant_id().unwrap_or_default();
                let mut filters = filters;
                // A channel's Files search names its folder.
                if filters.files && thread.ends_with("@thread.tacv2") && filters.channel_path.is_empty() {
                    let folder = api::drive::channel_folder(&client, &filters.channel_group, &thread).await?;
                    filters.channel_path = api::find::folder_path(&folder.web_url);
                }
                api::find::search(&client, &thread, &keywords, &filters, from, &api::find::local_timezone(), &oid, &tenant).await
            }
            .await;
            let _ = qt.queue(move |mut this| {
                if this.rust().find_key != key {
                    return;
                }
                let mut shown = shown;
                shown["loading"] = false.into();
                match result {
                    Ok(found) => {
                        let mut hits = shown["hits"].as_array().cloned().unwrap_or_default();
                        hits.extend(found.hits.iter().map(|h| json!(h)));
                        shown["hits"] = hits.into();
                        shown["total"] = found.total.into();
                        shown["more"] = found.more.into();
                        shown["terms"] = json!(found.terms);
                    }
                    Err(e) => {
                        tracing::warn!("find in chat failed: {}", short_error(&e));
                        shown["error"] = short_error(&e).into();
                    }
                }
                this.as_mut().set_find_json(QString::from(shown.to_string().as_str()));
            });
        });
    }

    pub fn feedback_issue_url(self: Pin<&mut Self>, report_json: &QString) -> QString {
        let report: teams_cli::feedback::Report = serde_json::from_str(&report_json.to_string()).unwrap_or_default();
        let logs = if report.share_logs {
            std::fs::read_to_string(crate::log_path())
                .map(|l| teams_cli::feedback::masked_tail(&l, 400))
                .unwrap_or_default()
        } else {
            String::new()
        };
        let version = format!("OST desktop {}", env!("CARGO_PKG_VERSION"));
        let url = teams_cli::feedback::issue_url(&report, &version, &teams_cli::feedback::os_name(), &logs);
        // GitHub takes pictures by paste: the first one goes on the clipboard.
        let picture = report.files.iter().find(|f| {
            let f = f.to_ascii_lowercase();
            [".png", ".jpg", ".jpeg", ".gif", ".bmp", ".webp"].iter().any(|e| f.ends_with(e))
        });
        if let Some(Ok(p)) = picture.map(|p| std::ffi::CString::new(p.as_str())) {
            // SAFETY: a NUL-terminated path, read by Qt before returning.
            unsafe { ost_set_clipboard_image(p.as_ptr()) };
        }
        QString::from(url.as_str())
    }

    pub fn feedback_link(&self, which: &QString) -> QString {
        let url = match which.to_string().as_str() {
            "ideas" => teams_cli::feedback::ideas_url(),
            "privacy" => teams_cli::feedback::privacy_url(""),
            "privacy-feedback" => teams_cli::feedback::privacy_url("feedback"),
            "docs" => teams_cli::feedback::docs_url(),
            _ => teams_cli::feedback::repo_url(),
        };
        QString::from(url.as_str())
    }

    pub fn request_feedback(self: Pin<&mut Self>, kind: &QString, area: &QString, context: &QString) {
        self.feedback_requested(kind.clone(), area.clone(), context.clone());
    }

    pub fn help_library(&self) -> QString {
        let lib = teams_cli::help::library(crate::help_bundle::FILES);
        QString::from(serde_json::to_string(&lib).unwrap_or_else(|_| "[]".into()).as_str())
    }

    pub fn help_search(&self, query: &QString) -> QString {
        let lib = teams_cli::help::library(crate::help_bundle::FILES);
        let found = teams_cli::help::search(&lib, &query.to_string());
        QString::from(serde_json::to_string(&found).unwrap_or_else(|_| "[]".into()).as_str())
    }

    pub fn feedback_dir(&self) -> QString {
        let base = std::env::var_os("XDG_CACHE_HOME")
            .map(std::path::PathBuf::from)
            .or_else(|| std::env::var_os("HOME").map(|h| std::path::PathBuf::from(h).join(".cache")))
            .unwrap_or_else(std::env::temp_dir);
        let dir = base.join("ost").join("feedback").join(chrono::Local::now().format("%Y-%m-%d %H-%M-%S").to_string());
        let _ = std::fs::create_dir_all(&dir);
        QString::from(dir.display().to_string().as_str())
    }

    pub fn paste_clipboard_image(&self, dir: &QString) -> QString {
        let dir = std::path::PathBuf::from(dir.to_string());
        let n = std::fs::read_dir(&dir).map(|d| d.count()).unwrap_or(0) + 1;
        let path = dir.join(format!("Pasted image {n}.png"));
        let Ok(c) = std::ffi::CString::new(path.display().to_string()) else { return QString::default() };
        // SAFETY: a NUL-terminated path, written by Qt before returning.
        if unsafe { ost_save_clipboard_image(c.as_ptr()) } {
            QString::from(path.display().to_string().as_str())
        } else {
            QString::default()
        }
    }

    pub fn search_page(mut self: Pin<&mut Self>, key: &QString, tab: &QString, keywords: &QString, filters_json: &QString, from: i32) {
        let key = key.to_string();
        let tab = tab.to_string();
        let keywords = keywords.to_string().trim().to_string();
        let filters: api::search::Filters = serde_json::from_str(&filters_json.to_string()).unwrap_or_default();
        let from = from.max(0) as usize;
        let mut shown: serde_json::Value = serde_json::from_str(&self.rust().search_page_json.to_string()).unwrap_or_default();
        if from == 0 || shown["key"] != key.as_str() {
            shown = json!({ "key": key, "tab": tab, "page": null });
        }
        shown["loading"] = true.into();
        shown["error"] = "".into();
        self.as_mut().rust_mut().search_page_key = key.clone();
        self.as_mut().set_search_page_json(QString::from(shown.to_string().as_str()));
        if keywords.is_empty() {
            shown["loading"] = false.into();
            self.as_mut().set_search_page_json(QString::from(shown.to_string().as_str()));
            return;
        }
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                let oid = client.object_id().unwrap_or_default();
                let tenant = client.tenant_id().unwrap_or_default();
                let mut page = api::search::search(&client, &tab, &keywords, &filters, from, &api::find::local_timezone(), &oid, &tenant).await?;
                // Images: the pictures, cached as the chat caches them.
                for h in page.images.hits.iter_mut().filter(|h| !h.image_ams.is_empty()) {
                    let img = api::messages::InlineImage { id: h.image_id.clone(), url: h.image_ams.clone(), width: 0, height: 0, local_path: String::new() };
                    if let Ok(path) = cached_image(&client, &img).await {
                        h.image_url = format!("file://{}", path.display());
                    }
                }
                anyhow::Ok(page)
            }
            .await;
            let _ = qt.queue(move |mut this| {
                if this.rust().search_page_key != key {
                    return;
                }
                let mut shown = shown;
                shown["loading"] = false.into();
                match result {
                    Ok(page) => {
                        let mut p = json!(page);
                        // More results: the earlier pages stay, the next appended.
                        if from > 0 {
                            for k in ["messages", "files", "images"] {
                                let mut hits = shown["page"][k]["hits"].as_array().cloned().unwrap_or_default();
                                hits.extend(p[k]["hits"].as_array().cloned().unwrap_or_default());
                                p[k]["hits"] = hits.into();
                            }
                        }
                        shown["page"] = p;
                    }
                    Err(e) => {
                        tracing::warn!("search failed: {}", short_error(&e));
                        shown["error"] = short_error(&e).into();
                    }
                }
                this.as_mut().set_search_page_json(QString::from(shown.to_string().as_str()));
            });
        });
    }

    pub fn search_in_suggest(self: Pin<&mut Self>, keyword: &QString) {
        let keyword = keyword.to_string().trim().to_string();
        if keyword.is_empty() {
            return;
        }
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = api::search::in_suggestions(&keyword).await;
            let groups: Vec<serde_json::Value> = match result {
                Ok(v) => v["Groups"].as_array().into_iter().flatten().map(|g| {
                    let items: Vec<serde_json::Value> = g["Suggestions"].as_array().into_iter().flatten().map(|x| json!({
                        "name": x["Name"], "thread": x["ThreadId"], "group": x["GroupId"], "team": x["TeamName"],
                        "kind": match x["EntityType"].as_str().unwrap_or_default() { "TeamSuggestion" => "team", "ChannelSuggestion" => "channel", _ => "chat" },
                    })).collect();
                    json!({ "type": g["Type"], "items": items })
                }).collect(),
                Err(e) => {
                    tracing::warn!("search In suggestions: {}", short_error(&e));
                    Vec::new()
                }
            };
            let v = json!({ "keyword": keyword, "groups": groups });
            let _ = qt.queue(move |mut this| this.as_mut().set_search_in_json(QString::from(v.to_string().as_str())));
        });
    }

    pub fn find_people(self: Pin<&mut Self>, channel: &QString, keyword: &QString) {
        let (channel, keyword) = (channel.to_string(), keyword.to_string().trim().to_string());
        if channel.is_empty() || keyword.is_empty() {
            return;
        }
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                api::channels::profile_search(&client, &channel, &keyword, 15, true).await
            }
            .await;
            let people: Vec<serde_json::Value> = match result {
                Ok(p) => p.iter().map(|p| json!({ "mri": p.mri, "name": p.name, "mail": p.mail })).collect(),
                Err(e) => {
                    tracing::warn!("find people: {}", short_error(&e));
                    Vec::new()
                }
            };
            let v = json!({ "keyword": keyword, "people": people });
            let _ = qt.queue(move |mut this| this.as_mut().set_find_people_json(QString::from(v.to_string().as_str())));
        });
    }

    pub fn find_file_action(mut self: Pin<&mut Self>, op: &QString, url: &QString) {
        let (op, url) = (op.to_string(), url.to_string());
        if !url.starts_with("https://") {
            return;
        }
        let dir = if op == "download" {
            let Some(d) = download_dir() else { return };
            Some(d)
        } else {
            None
        };
        let qt = self.qt_thread();
        self.as_mut().set_status_text(QString::from(if op == "download" { "Downloading…" } else { "" }));
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                let item = api::drive::item_by_url(&client, &url).await?;
                match dir {
                    Some(dir) => {
                        let path = api::drive::download(&client, &item, &dir).await?;
                        Ok(format!(
                            "Saved {} to {}",
                            item.name,
                            path.parent().map(|p| p.display().to_string()).unwrap_or_default()
                        ))
                    }
                    None => {
                        api::drive::set_favorite(&client, &item.drive_id, &item.id, true).await?;
                        Ok(format!("Added {} to Favorites", item.name))
                    }
                }
            }
            .await;
            let msg = match result {
                Ok(m) => m,
                Err(e) => short_error(&e),
            };
            let _ = qt.queue(move |mut this| this.as_mut().set_status_text(QString::from(msg.as_str())));
        });
    }

    pub fn cancel_scheduled(self: Pin<&mut Self>, id: &QString) {
        let id = id.to_string();
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                api::scheduled::cancel(&client, &id).await
            }
            .await;
            let _ = qt.queue(move |mut this| match result {
                Ok(()) => this.as_mut().load_scheduled(),
                Err(e) => this.as_mut().set_status_text(QString::from(short_error(&e).as_str())),
            });
        });
    }

    pub fn edit_scheduled(
        self: Pin<&mut Self>,
        id: &QString,
        client_message_id: &QString,
        editor_html: &QString,
        media_json: &QString,
        send_at_ms: &QString,
    ) {
        let Ok(at_ms) = send_at_ms.to_string().parse::<i64>() else { return };
        let media: Vec<api::messages::ComposeMedia> =
            serde_json::from_str(&media_json.to_string()).unwrap_or_default();
        let (html, mentions) = api::messages::teams_html_with_media(&editor_html.to_string(), &media);
        let chat_id = self.rust().current_chat_id.to_string();
        if chat_id.is_empty() || html.trim().is_empty() {
            return;
        }
        let mentions = if mentions.is_empty() { String::new() } else { serde_json::to_string(&mentions).unwrap_or_default() };
        let mut o = self.outgoing(&chat_id, chat_id.clone(), html, mentions, None, String::new());
        if !client_message_id.is_empty() {
            o.client_message_id = client_message_id.to_string();
        }
        let id = id.to_string();
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                api::scheduled::edit(&client, &id, &o, at_ms).await
            }
            .await;
            let _ = qt.queue(move |mut this| match result {
                Ok(()) => this.as_mut().load_scheduled(),
                Err(e) => {
                    tracing::warn!("scheduled edit failed: {}", short_error(&e));
                    this.as_mut().set_status_text(QString::from("Failed to edit scheduled message"))
                }
            });
        });
    }

    /// Schedule `o` (Teams' Schedule message), then show it waiting.
    fn schedule_outgoing(self: Pin<&mut Self>, o: api::outbox::Outgoing, at_ms: i64) {
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                api::scheduled::schedule(&client, &o, at_ms).await
            }
            .await;
            let _ = qt.queue(move |mut this| match result {
                Ok(_) => this.as_mut().load_scheduled(),
                Err(e) => {
                    tracing::warn!("schedule failed: {}", short_error(&e));
                    this.as_mut().set_status_text(QString::from("Failed to schedule."))
                }
            });
        });
    }

    /// Fetch the open chat's members (names and e-mail from Graph).
    /// A meeting chat's meeting (for the header's Join).
    fn load_chat_meeting(mut self: Pin<&mut Self>) {
        let chat_id = self.rust().current_chat_id.to_string();
        self.as_mut().set_chat_meeting_json(QString::default());
        if !chat_id.starts_with("19:meeting_") {
            return;
        }
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                api::chat_meeting(&client, &chat_id).await
            }
            .await;
            let _ = qt.queue(move |mut this| {
                if this.rust().current_chat_id.to_string() != chat_id {
                    return;
                }
                match result {
                    Ok(Some(m)) => {
                        let text = serde_json::to_string(&m).unwrap_or_default();
                        this.as_mut()
                            .set_chat_meeting_json(QString::from(text.as_str()));
                    }
                    Ok(None) => {}
                    Err(e) => tracing::warn!("meeting unavailable: {}", short_error(&e)),
                }
            });
        });
    }

    fn load_chat_members(mut self: Pin<&mut Self>) {
        let chat_id = self.rust().current_chat_id.to_string();
        self.as_mut().set_chat_members_json(QString::from("[]"));
        if chat_id.is_empty() || chat_id.ends_with("@thread.tacv2") || chat_id.starts_with("48:") {
            return;
        }
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = members_with_presence(&chat_id).await;
            let _ = qt.queue(move |mut this| {
                if this.rust().current_chat_id.to_string() != chat_id {
                    return;
                }
                match result {
                    Ok(text) => this
                        .as_mut()
                        .set_chat_members_json(QString::from(text.as_str())),
                    Err(e) => tracing::warn!("chat members unavailable: {}", short_error(&e)),
                }
            });
        });
    }

    /// The call's chat members (a meeting's or group's thread).
    fn load_call_chat_members(mut self: Pin<&mut Self>) {
        let thread = self.rust().call_thread_id.to_string();
        self.as_mut()
            .set_call_chat_members_json(QString::from("[]"));
        if thread.is_empty() {
            return;
        }
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = members_with_presence(&thread).await;
            let _ = qt.queue(move |mut this| {
                if this.rust().call_thread_id.to_string() != thread {
                    return;
                }
                match result {
                    Ok(text) => this
                        .as_mut()
                        .set_call_chat_members_json(QString::from(text.as_str())),
                    Err(e) => tracing::info!("call chat members unavailable: {}", short_error(&e)),
                }
            });
        });
    }

    pub fn send_message(self: Pin<&mut Self>, text: &QString) {
        let body = text.to_string();
        let chat_id = self.rust().current_chat_id.to_string();
        if body.trim().is_empty() || chat_id.is_empty() {
            return;
        }
        self.enqueue(chat_id, api::outbox::plain_html(&body));
    }

    /// The conversation a message action applies to: where that message
    /// is shown, the open chat or a thread window's channel.
    fn chat_of(&self, message_id: &str) -> String {
        let current = self.rust().current_chat_id.to_string();
        let timelines = server_timelines().lock().unwrap();
        let has = |key: &str| {
            timelines
                .get(key)
                .is_some_and(|t| t.iter().any(|m| m.id == message_id))
        };
        if current.is_empty() || has(&current) {
            return current;
        }
        self.rust()
            .thread_windows
            .iter()
            .find(|t| has(t))
            .map(|t| window_channel(t).to_string())
            .unwrap_or(current)
    }

    /// The messages shown for `chat` (JSON array): the open chat's, or
    /// those of the thread windows in that channel.
    fn shown_json_of(&self, chat: &str) -> String {
        if chat == self.rust().current_chat_id.to_string() {
            return self.rust().messages_json.to_string();
        }
        let channel = chat.split(';').next().unwrap_or_default();
        let all: serde_json::Value =
            serde_json::from_str(&self.rust().thread_windows_json.to_string()).unwrap_or_default();
        let list: Vec<serde_json::Value> = all
            .as_object()
            .into_iter()
            .flatten()
            .filter(|(k, _)| window_channel(k) == channel)
            .flat_map(|(_, v)| v.as_array().cloned().unwrap_or_default())
            .collect();
        serde_json::to_string(&list).unwrap_or_else(|_| "[]".into())
    }

    /// Something changed in `chat`: reload it where it shows (the open
    /// chat, and the thread windows of that channel).
    fn reload_where(mut self: Pin<&mut Self>, chat: &str) {
        let channel = chat.split(';').next().unwrap_or_default().to_string();
        if self.rust().current_chat_id.to_string() == channel || self.rust().current_chat_id.to_string() == chat {
            self.as_mut().reload_messages();
        }
        let open: Vec<String> = self
            .rust()
            .thread_windows
            .iter()
            .filter(|t| window_channel(t) == channel.as_str())
            .cloned()
            .collect();
        for t in open {
            self.as_mut().reload_thread_window(t);
        }
    }

    pub fn open_thread_window(mut self: Pin<&mut Self>, channel_id: &QString, root_id: &QString) {
        let (channel, root) = (channel_id.to_string(), root_id.to_string());
        if !channel.ends_with("@thread.tacv2") || root.is_empty() || !root.bytes().all(|b| b.is_ascii_digit()) {
            return;
        }
        let thread = format!("{channel};messageid={root}");
        if !self.rust().thread_windows.contains(&thread) {
            self.as_mut().rust_mut().thread_windows.push(thread.clone());
        }
        self.as_mut().refresh_thread_windows();
        self.as_mut().reload_thread_window(thread);
    }

    pub fn close_thread_window(mut self: Pin<&mut Self>, channel_id: &QString, root_id: &QString) {
        let thread = format!("{};messageid={}", channel_id, root_id);
        self.as_mut().rust_mut().thread_windows.retain(|t| *t != thread);
        server_timelines().lock().unwrap().remove(&thread);
        self.as_mut().refresh_thread_windows();
    }

    pub fn open_channel_window(mut self: Pin<&mut Self>, channel_id: &QString) {
        let channel = channel_id.to_string();
        if !channel.ends_with("@thread.tacv2") {
            return;
        }
        let key = format!("win:{channel}");
        if !self.rust().thread_windows.contains(&key) {
            self.as_mut().rust_mut().thread_windows.push(key.clone());
        }
        self.as_mut().refresh_thread_windows();
        self.as_mut().reload_thread_window(key);
    }

    pub fn open_chat_window(mut self: Pin<&mut Self>, chat_id: &QString) {
        let chat = chat_id.to_string();
        if !is_chat_id(&chat) {
            return;
        }
        let key = format!("win:{chat}");
        if !self.rust().thread_windows.contains(&key) {
            self.as_mut().rust_mut().thread_windows.push(key.clone());
        }
        self.as_mut().refresh_thread_windows();
        self.as_mut().reload_thread_window(key);
    }

    pub fn close_chat_window(mut self: Pin<&mut Self>, chat_id: &QString) {
        let key = format!("win:{}", chat_id);
        self.as_mut().rust_mut().thread_windows.retain(|t| *t != key);
        server_timelines().lock().unwrap().remove(&key);
        self.as_mut().refresh_thread_windows();
    }

    pub fn send_chat_window_message(
        self: Pin<&mut Self>,
        chat_id: &QString,
        editor_html: &QString,
        media_json: &QString,
        quote_json: &QString,
    ) {
        let chat = chat_id.to_string();
        if !is_chat_id(&chat) {
            return;
        }
        let media: Vec<api::messages::ComposeMedia> =
            serde_json::from_str(&media_json.to_string()).unwrap_or_default();
        let (html, mentions) = api::messages::teams_html_with_media(&editor_html.to_string(), &media);
        if html.trim().is_empty() {
            return;
        }
        let mentions = if mentions.is_empty() { String::new() } else { serde_json::to_string(&mentions).unwrap_or_default() };
        let quote: Option<api::messages::Quote> = serde_json::from_str(&quote_json.to_string()).ok();
        let o = self.outgoing(&format!("win:{chat}"), chat.clone(), html, mentions, quote, String::new());
        self.submit_outgoing(o);
    }

    pub fn send_chat_window_files(self: Pin<&mut Self>, chat_id: &QString, paths: &QString, text: &QString) {
        let chat = chat_id.to_string();
        if !is_chat_id(&chat) {
            return;
        }
        self.send_files_in(chat.clone(), chat, paths, text);
    }

    pub fn close_channel_window(mut self: Pin<&mut Self>, channel_id: &QString) {
        let key = format!("win:{}", channel_id);
        self.as_mut().rust_mut().thread_windows.retain(|t| *t != key);
        server_timelines().lock().unwrap().remove(&key);
        self.as_mut().refresh_thread_windows();
    }

    pub fn send_channel_post(
        mut self: Pin<&mut Self>,
        channel_id: &QString,
        editor_html: &QString,
        media_json: &QString,
        quote_json: &QString,
    ) {
        let channel = channel_id.to_string();
        if !channel.ends_with("@thread.tacv2") {
            return;
        }
        let media: Vec<api::messages::ComposeMedia> =
            serde_json::from_str(&media_json.to_string()).unwrap_or_default();
        let (html, mentions) =
            api::messages::teams_html_with_media(&editor_html.to_string(), &media);
        if html.trim().is_empty() {
            return;
        }
        if html.len() > api::outbox::MAX_MESSAGE_CONTENT_SIZE {
            self.as_mut()
                .set_status_text(QString::from(api::outbox::TOO_LARGE_TO_SEND));
            return;
        }
        let mentions = if mentions.is_empty() {
            String::new()
        } else {
            serde_json::to_string(&mentions).unwrap_or_default()
        };
        let quote: Option<api::messages::Quote> =
            serde_json::from_str(&quote_json.to_string()).ok();
        let mut o = self.outgoing(&format!("win:{channel}"), channel.clone(), html, mentions, quote, String::new());
        self.as_mut().apply_next_post(&mut o);
        self.submit_outgoing(o);
    }

    /// Load a thread window's post and replies again.
    fn reload_thread_window(self: Pin<&mut Self>, thread: String) {
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = load_thread(&thread).await;
            let _ = qt.queue(move |mut this| match result {
                Ok(()) => this.as_mut().refresh_thread_windows(),
                Err(e) => tracing::warn!("thread not loaded: {}", short_error(&e)),
            });
        });
    }

    /// thread_windows_json from the loaded threads and what is being sent.
    fn refresh_thread_windows(mut self: Pin<&mut Self>) {
        let mut all = serde_json::Map::new();
        for thread in self.rust().thread_windows.clone() {
            let timeline = server_timelines()
                .lock()
                .unwrap()
                .get(&thread)
                .cloned()
                .unwrap_or_default();
            let shown = with_thread_lies(&thread, timeline);
            all.insert(thread, serde_json::to_value(&shown).unwrap_or_default());
        }
        let json = serde_json::Value::Object(all).to_string();
        if self.rust().thread_windows_json.to_string() != json {
            self.as_mut()
                .set_thread_windows_json(QString::from(json.as_str()));
        }
    }

    pub fn send_thread_reply(
        mut self: Pin<&mut Self>,
        channel_id: &QString,
        root_id: &QString,
        editor_html: &QString,
        media_json: &QString,
        quote_json: &QString,
        also_channel: bool,
    ) {
        let (channel, root) = (channel_id.to_string(), root_id.to_string());
        if !channel.ends_with("@thread.tacv2") || root.is_empty() || !root.bytes().all(|b| b.is_ascii_digit()) {
            return;
        }
        let media: Vec<api::messages::ComposeMedia> =
            serde_json::from_str(&media_json.to_string()).unwrap_or_default();
        let (html, mentions) =
            api::messages::teams_html_with_media(&editor_html.to_string(), &media);
        if html.trim().is_empty() {
            return;
        }
        if html.len() > api::outbox::MAX_MESSAGE_CONTENT_SIZE {
            self.as_mut()
                .set_status_text(QString::from(api::outbox::TOO_LARGE_TO_SEND));
            return;
        }
        let mentions = if mentions.is_empty() {
            String::new()
        } else {
            serde_json::to_string(&mentions).unwrap_or_default()
        };
        let quote: Option<api::messages::Quote> =
            serde_json::from_str(&quote_json.to_string()).ok();
        let thread = format!("{channel};messageid={root}");
        let mut o = self.outgoing(&thread, thread.clone(), html, mentions, quote, String::new());
        o.shared_in_main = also_channel;
        let _rt = runtime().enter();
        outbox().submit(o);
    }

    pub fn send_reply(self: Pin<&mut Self>, root_id: &QString, text: &QString) {
        let (root, body) = (root_id.to_string(), text.to_string());
        let channel = self.rust().current_chat_id.to_string();
        // Replies go to "<channel>;messageid=<post>"; post ids are digits.
        if body.trim().is_empty()
            || !channel.ends_with("@thread.tacv2")
            || root.is_empty()
            || !root.bytes().all(|b| b.is_ascii_digit())
        {
            return;
        }
        self.enqueue(
            format!("{channel};messageid={root}"),
            api::outbox::plain_html(&body),
        );
    }

    /// Send as Teams does: the message shows at once (Sending) and goes
    /// through the outbox, which retries and queues it as Teams' send
    /// pipeline does (docs/spec/send-pipeline.md).
    fn enqueue(self: Pin<&mut Self>, conversation: String, content: String) {
        self.enqueue_with(conversation, content, String::new())
    }

    fn enqueue_with(
        mut self: Pin<&mut Self>,
        conversation: String,
        content: String,
        mentions: String,
    ) {
        let schedule = self.as_mut().rust_mut().next_schedule_ms.take();
        if content.len() > api::outbox::MAX_MESSAGE_CONTENT_SIZE {
            // Teams' words for each.
            let text = if schedule.is_some() { "Failed to schedule. Message too large." } else { api::outbox::TOO_LARGE_TO_SEND };
            self.as_mut().set_status_text(QString::from(text));
            return;
        }
        if schedule.is_some_and(|ms| ms <= chrono::Utc::now().timestamp_millis()) {
            self.as_mut()
                .set_status_text(QString::from("This message was scheduled for a time in the past."));
            return;
        }
        let chat_id = self.rust().current_chat_id.to_string();
        let quote = self.as_mut().rust_mut().reply_quote.take();
        let importance = std::mem::take(&mut self.as_mut().rust_mut().next_importance);
        let mut o = self.outgoing(&chat_id, conversation, content, mentions, quote, importance);
        self.as_mut().apply_next_post(&mut o);
        // Sent: the draft for this chat is done.
        self.as_mut()
            .set_draft(&QString::from(chat_id.as_str()), &QString::default());
        match schedule {
            Some(ms) => self.schedule_outgoing(o, ms),
            None => self.submit_outgoing(o),
        }
    }

    /// A message to send: its arrival placed after the newest message of
    /// `timeline` (the conversation shown), sent or still being sent.
    fn outgoing(
        &self,
        timeline: &str,
        conversation: String,
        content: String,
        mentions: String,
        quote: Option<api::messages::Quote>,
        importance: String,
    ) -> api::outbox::Outgoing {
        let chat_id = timeline.to_string();
        let content = match &quote {
            Some(q) => format!("{}{}", api::messages::quote_html(q), content),
            None => content,
        };
        let now = chrono::Utc::now().timestamp_millis();
        // The newest message in the chat, sent or still being sent.
        let last_server = server_timelines()
            .lock()
            .unwrap()
            .get(&chat_id)
            .and_then(|t| t.iter().filter_map(|m| m.id.parse::<i64>().ok()).max());
        let last_lie = outbox()
            .for_conversation(&chat_id)
            .iter()
            .map(|o| o.arrival_ms)
            .max();
        let last = last_server.max(last_lie);
        api::outbox::Outgoing {
            conversation_id: conversation,
            client_message_id: api::outbox::new_client_message_id(),
            content,
            display_name: self.rust().user_name.to_string(),
            sender_mri: self.rust().my_mri.clone().unwrap_or_default(),
            compose_time: chrono::Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Millis, true),
            arrival_ms: api::outbox::lie_arrival(now, last),
            created_ms: now,
            state: api::outbox::SendState::Sending,
            pipeline_status: None,
            failures: 0,
            queued: true,
            server_id: None,
            quote,
            importance,
            mentions,
            subject: String::new(),
            title: String::new(),
            banner_theme: None,
            banner_image: None,
            shared_in_main: false,
            threads_layout: false,
        }
    }

    pub fn copy_message_link(&self, message_json: &QString, place_json: &QString) {
        let m: serde_json::Value =
            serde_json::from_str(&message_json.to_string()).unwrap_or_default();
        let place: serde_json::Value =
            serde_json::from_str(&place_json.to_string()).unwrap_or_default();
        let field = |v: &serde_json::Value, k: &str| {
            QString::from(v.get(k).and_then(|x| x.as_str()).unwrap_or_default())
        };
        let (message_id, sender, text, root_id) = (
            field(&m, "id"),
            field(&m, "sender"),
            field(&m, "text"),
            field(&m, "root_id"),
        );
        let (team_id, team_name, channel_name) = (
            field(&place, "team_id"),
            field(&place, "team_name"),
            field(&place, "channel_name"),
        );
        let conv = self.current_chat_id.to_string();
        let id = message_id.to_string();
        let channel = conv.ends_with("@thread.tacv2");
        let (url, label) = if channel {
            let tenant = teams_cli::config::Config::load()
                .ok()
                .and_then(|c| c.tenant_id())
                .unwrap_or_default();
            let root = root_id.to_string();
            let parent = if root.is_empty() { id.clone() } else { root };
            let created: i64 = id.parse().unwrap_or(0);
            (
                api::msgactions::channel_message_link(
                    &conv,
                    &id,
                    &parent,
                    &tenant,
                    &team_id.to_string(),
                    &team_name.to_string(),
                    &channel_name.to_string(),
                    created,
                    false,
                    false,
                ),
                api::msgactions::copy_link_text(
                    &sender.to_string(),
                    &text.to_string(),
                    Some(&channel_name.to_string()),
                ),
            )
        } else {
            let oid = self
                .my_mri
                .as_deref()
                .and_then(|m| m.strip_prefix("8:orgid:"))
                .unwrap_or_default()
                .to_string();
            (
                api::msgactions::chat_message_link(&conv, &id, None, &oid),
                api::msgactions::copy_link_text(&sender.to_string(), &text.to_string(), None),
            )
        };
        let html = api::msgactions::copy_link_html(&url, &label, channel);
        let (Ok(url), Ok(html)) = (std::ffi::CString::new(url), std::ffi::CString::new(html))
        else {
            return;
        };
        // SAFETY: two NUL-terminated strings, copied by Qt before returning.
        unsafe { ost_set_clipboard(url.as_ptr(), html.as_ptr()) };
    }

    pub fn copy_chat_link(self: Pin<&mut Self>) {
        let chat_id = self.rust().current_chat_id.clone();
        let name = self.rust().current_chat_name.clone();
        self.copy_link_of_chat(&chat_id, &name);
    }

    pub fn copy_link_of_chat(mut self: Pin<&mut Self>, chat_id: &QString, chat_name: &QString) {
        let chat_id = chat_id.to_string();
        if chat_id.is_empty() {
            return;
        }
        let url = api::msgactions::chat_link(&chat_id);
        let name = chat_name.to_string();
        let html = format!(
            "<a href=\"{}\">{}</a>",
            url.replace('"', "&quot;"),
            name.replace('&', "&amp;").replace('<', "&lt;")
        );
        if let (Ok(u), Ok(h)) = (std::ffi::CString::new(url), std::ffi::CString::new(html)) {
            // SAFETY: two NUL-terminated strings, copied by Qt before returning.
            unsafe { ost_set_clipboard(u.as_ptr(), h.as_ptr()) };
            self.as_mut().toast("Copied to clipboard", "success");
        }
    }

    pub fn custom_emoji_send_url(&self, document_id: &QString) -> QString {
        let base = teams_cli::config::Config::load()
            .ok()
            .and_then(|c| c.get_region_gtms())
            .and_then(|g| {
                g.get("amsV2")
                    .and_then(|v| v.as_str())
                    .map(|u| u.trim_end_matches('/').to_string())
            })
            .unwrap_or_else(|| "https://us-prod.asyncgw.teams.microsoft.com".into());
        QString::from(
            api::custom_emoji::picture_url(&base, &document_id.to_string(), true).as_str(),
        )
    }

    pub fn load_custom_emoji(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                let list = api::custom_emoji::list(&client).await?;
                // Creators by name, for "Created by … on …".
                let mut out = Vec::new();
                for e in list {
                    // `creator` may be "{prefix}_{oid without dashes}" (unconfirmed);
                    // Graph takes the plain oid or MRI forms.
                    let name = if e.creator.is_empty() { String::new() } else {
                        api::user_display_name(&client, &e.creator).await.unwrap_or_default()
                    };
                    out.push(json!({"id": e.id, "shortcut": e.shortcut, "document_id": e.document_id, "creator": e.creator, "created_on": e.created_on, "creator_name": name}));
                }
                // What the policy allows (Teams: create on unless off,
                // delete off unless on).
                let policy = api::custom_emoji::messaging_policy(&client).await.unwrap_or_default();
                let can_add = api::custom_emoji::find_bool(&policy, "createCustomEmojis").unwrap_or(true);
                let can_delete = api::custom_emoji::find_bool(&policy, "deleteCustomEmojis").unwrap_or(false);
                anyhow::Ok((out, can_add, can_delete))
            }
            .await;
            let _ = qt.queue(move |mut this| match result {
                Ok((list, can_add, can_delete)) => {
                    this.as_mut().set_custom_emoji_can_add(can_add);
                    this.as_mut().set_custom_emoji_can_delete(can_delete);
                    this.as_mut()
                        .set_custom_emoji_json(QString::from(json!(list).to_string().as_str()))
                }
                Err(e) => tracing::warn!("custom emoji unavailable: {}", short_error(&e)),
            });
        });
    }

    pub fn add_custom_emoji(mut self: Pin<&mut Self>, name: &QString, path: &QString) {
        let name = name.to_string().trim().to_string();
        let path = path.to_string().trim_start_matches("file://").to_string();
        if !api::custom_emoji::valid_name(&name) {
            return;
        }
        self.as_mut()
            .set_custom_emoji_result(QString::from("adding"));
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let bytes = std::fs::read(&path)
                    .map_err(|e| api::custom_emoji::AddError::Other(e.to_string()))?;
                let client = TeamsClient::new()
                    .await
                    .map_err(|e| api::custom_emoji::AddError::Other(format!("{e:#}")))?;
                api::custom_emoji::add(&client, &name, bytes).await
            }
            .await;
            let outcome = match &result {
                Ok(_) => "ok".to_string(),
                Err(api::custom_emoji::AddError::AlreadyPresent) => "duplicate".into(),
                Err(api::custom_emoji::AddError::MaxLimitReached(n)) => format!("limit:{n}"),
                Err(e) => {
                    tracing::warn!("custom emoji not added: {e:?}");
                    "error".into()
                }
            };
            let _ = qt.queue(move |mut this| {
                if outcome == "ok" {
                    this.as_mut().toast(&format!("{name} was added"), "success");
                    this.as_mut().load_custom_emoji();
                }
                this.as_mut()
                    .set_custom_emoji_result(QString::from(outcome.as_str()));
            });
        });
    }

    pub fn delete_custom_emoji(self: Pin<&mut Self>, id: &QString) {
        let id = id.to_string();
        let Some(e) = api::custom_emoji::CustomEmoji::from_id(&id) else {
            return;
        };
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                api::custom_emoji::delete(&client, &id).await
            }
            .await;
            let _ = qt.queue(move |mut this| match result {
                Ok(()) => {
                    this.as_mut().toast(
                        &format!("{} deleted for your organization.", e.shortcut),
                        "success",
                    );
                    this.as_mut().load_custom_emoji();
                }
                Err(err) => {
                    tracing::warn!("custom emoji not deleted: {}", short_error(&err));
                    this.as_mut()
                        .toast("Unable to delete. Please try again.", "error");
                }
            });
        });
    }

    pub fn search_gifs(self: Pin<&mut Self>, query: &QString) {
        static GENERATION: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
        let generation = GENERATION.fetch_add(1, Ordering::SeqCst) + 1;
        let query = query.to_string();
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                // Teams' default GIPHY rating ("Moderate" → g), in the UI's language.
                api::funstuff::search_raw(
                    &client,
                    api::funstuff::FunKind::Gifs,
                    &query,
                    "g",
                    "en-us",
                )
                .await
            }
            .await;
            let json = match result {
                Ok(v) => json!({ "query": query, "items": api::funstuff::items(&v) }),
                Err(e) => json!({ "query": query, "items": [], "error": short_error(&e) }),
            };
            let _ = qt.queue(move |mut this| {
                // Only the newest search counts (typing fires several).
                if GENERATION.load(Ordering::SeqCst) == generation {
                    this.as_mut()
                        .set_fun_results_json(QString::from(json.to_string().as_str()));
                }
            });
        });
    }

    pub fn set_chat_unread(mut self: Pin<&mut Self>, chat_id: &QString, unread: bool) {
        let chat_id = chat_id.to_string();
        if chat_id.is_empty() {
            return;
        }
        let changed = if unread {
            self.as_mut().rust_mut().unread.insert(chat_id.clone())
        } else {
            self.as_mut().rust_mut().unread.remove(&chat_id)
        };
        if changed {
            self.as_mut().publish_chats();
        }
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                if unread {
                    api::messages::mark_chat_unread_from_latest(&client, &chat_id).await
                } else {
                    api::messages::mark_chat_read_to_latest(&client, &chat_id).await
                }
            }
            .await;
            if let Err(e) = result {
                tracing::warn!("mark read/unread failed: {}", short_error(&e));
            }
        });
    }

    pub fn add_chat_members(mut self: Pin<&mut Self>, mris_json: &QString, days: i32) {
        let chat_id = self.rust().current_chat_id.to_string();
        let mris: Vec<String> = serde_json::from_str(&mris_json.to_string()).unwrap_or_default();
        if chat_id.is_empty() || mris.is_empty() {
            return;
        }
        let history = match days {
            d if d < 0 => api::msgactions::SharedHistory::None,
            0 => api::msgactions::SharedHistory::All,
            d => api::msgactions::SharedHistory::Days(d as u32),
        };
        self.as_mut()
            .set_status_text(QString::from("Adding people…"));
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                api::msgactions::add_chat_members(&client, &chat_id, &mris, history).await
            }
            .await;
            let _ = qt.queue(move |mut this| match result {
                Ok(()) => {
                    this.as_mut().set_status_text(QString::from(""));
                    this.as_mut().load_chat_members();
                }
                Err(e) => this.as_mut().set_status_text(QString::from(
                    format!("Couldn't add people: {}", short_error(&e)).as_str(),
                )),
            });
        });
    }

    pub fn copy_text(mut self: Pin<&mut Self>, text: &QString) {
        if let Ok(t) = std::ffi::CString::new(text.to_string()) {
            // SAFETY: a NUL-terminated string (and an empty one), copied by
            // Qt before returning.
            unsafe { ost_set_clipboard(t.as_ptr(), c"".as_ptr()) };
            self.as_mut().toast("Copied to clipboard", "success");
        }
    }

    pub fn remove_chat_member(self: Pin<&mut Self>, mri: &QString) {
        let chat_id = self.rust().current_chat_id.to_string();
        let mri = mri.to_string();
        if chat_id.is_empty() || mri.is_empty() {
            return;
        }
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                api::msgactions::remove_chat_member(&client, &chat_id, &mri).await
            }
            .await;
            let _ = qt.queue(move |mut this| match result {
                Ok(()) => this.as_mut().load_chat_members(),
                Err(e) => this.as_mut().set_status_text(QString::from(
                    format!("Couldn't remove them: {}", short_error(&e)).as_str(),
                )),
            });
        });
    }

    pub fn set_chat_muted(mut self: Pin<&mut Self>, chat_id: &QString, muted: bool) {
        let chat_id = chat_id.to_string();
        if chat_id.is_empty() || chat_id.starts_with("48:") {
            return;
        }
        // Show it at once, as Teams does; the reload confirms or undoes it.
        if let Some(c) = self
            .as_mut()
            .rust_mut()
            .chats
            .iter_mut()
            .find(|c| c["id"].as_str() == Some(chat_id.as_str()))
        {
            c["muted"] = json!(muted);
        }
        self.as_mut().publish_chats();
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                api::msgactions::set_chat_muted(&client, &chat_id, muted).await
            }
            .await;
            let _ = qt.queue(move |mut this| {
                if let Err(e) = &result {
                    this.as_mut()
                        .set_status_text(QString::from(short_error(e).as_str()));
                }
                this.as_mut().reload_chats();
            });
        });
    }

    pub fn rename_chat(mut self: Pin<&mut Self>, topic: &QString) {
        let topic = topic.to_string().trim().to_string();
        let chat_id = self.rust().current_chat_id.to_string();
        if topic.is_empty()
            || topic.chars().count() > 250
            || topic.contains(':')
            || chat_id.is_empty()
        {
            return;
        }
        self.as_mut()
            .set_current_chat_name(QString::from(topic.as_str()));
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                api::msgactions::set_chat_topic(&client, &chat_id, &topic).await
            }
            .await;
            let _ = qt.queue(move |mut this| match result {
                Ok(()) => this.as_mut().reload_chats(),
                Err(e) => this
                    .as_mut()
                    .set_status_text(QString::from(short_error(&e).as_str())),
            });
        });
    }

    /// Change a flag on a message in the open chat's last timeline, then
    /// redraw.
    fn update_shown(
        mut self: Pin<&mut Self>,
        message_id: &str,
        f: impl Fn(&mut api::messages::MessageView),
    ) {
        let chat_id = self.chat_of(message_id);
        let channel = chat_id.split(';').next().unwrap_or_default().to_string();
        for (key, t) in server_timelines().lock().unwrap().iter_mut() {
            if *key == chat_id || window_channel(key) == channel.as_str() {
                for m in t.iter_mut().filter(|m| m.id == message_id) {
                    f(m);
                }
            }
        }
        self.as_mut().refresh_lies();
    }

    pub fn set_message_saved(mut self: Pin<&mut Self>, message_id: &QString, save: bool) {
        let (chat_id, id) = (
            self.chat_of(&message_id.to_string()),
            message_id.to_string(),
        );
        // Teams flips the label at once and puts it back if the save fails.
        self.as_mut().update_shown(&id, |m| m.saved = save);
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                api::msgactions::set_saved(&client, &chat_id, "", &id, save).await
            }
            .await;
            if let Err(e) = result {
                tracing::warn!("save failed: {}", short_error(&e));
                let _ = qt.queue(move |mut this| {
                    this.as_mut().update_shown(&id, |m| m.saved = !save);
                    let msg = if save {
                        "Your item couldn't be saved"
                    } else {
                        "Your item couldn't be unsaved"
                    };
                    this.as_mut().set_status_text(QString::from(msg));
                });
            }
        });
    }

    pub fn mark_message_unread(
        mut self: Pin<&mut Self>,
        message_id: &QString,
        client_message_id: &QString,
    ) {
        let (chat_id, id, cmid) = (
            self.chat_of(&message_id.to_string()),
            message_id.to_string(),
            client_message_id.to_string(),
        );
        let Ok(arrival) = id.parse::<i64>() else {
            return;
        };
        // The chat shows as unread in the list (Teams' bookmark).
        if self.as_mut().rust_mut().unread.insert(chat_id.clone()) {
            self.as_mut().publish_chats();
        }
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                api::msgactions::mark_unread(&client, &chat_id, arrival, &cmid).await
            }
            .await;
            if let Err(e) = result {
                tracing::warn!("mark as unread failed: {}", short_error(&e));
            }
        });
    }

    pub fn set_message_pinned(mut self: Pin<&mut Self>, message_id: &QString, pin: bool) {
        let (chat_id, id) = (
            self.chat_of(&message_id.to_string()),
            message_id.to_string(),
        );
        self.as_mut().update_shown(&id, |m| m.pinned = pin);
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                api::msgactions::set_pinned(&client, &chat_id, &id, pin).await
            }
            .await;
            let _ = qt.queue(move |mut this| match result {
                Ok(order) => {
                    // The pins kept are the open chat's.
                    if this.rust().current_chat_id.to_string() == chat_id {
                        *pinned_order().lock().unwrap() = (chat_id.clone(), order);
                    }
                    this.as_mut().reload_where(&chat_id);
                }
                Err(e) => {
                    tracing::warn!("pin failed: {}", short_error(&e));
                    this.as_mut().update_shown(&id, |m| m.pinned = !pin);
                    let msg = if pin {
                        "Couldn't pin message"
                    } else {
                        "Couldn't unpin message"
                    };
                    this.as_mut().set_status_text(QString::from(msg));
                }
            });
        });
    }

    pub fn load_message_readers(self: Pin<&mut Self>, message_id: &QString) {
        let (chat_id, id) = (
            self.rust().current_chat_id.to_string(),
            message_id.to_string(),
        );
        let Ok(arrival) = id.parse::<u64>() else {
            return;
        };
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                let (mris, total) = api::msgactions::readers(&client, &chat_id, arrival).await?;
                let mut readers = Vec::new();
                for mri in mris {
                    let name = api::messages::person_name(&client, &mri)
                        .await
                        .unwrap_or_else(|| "Unknown user".into());
                    readers.push(json!({ "mri": mri, "name": name }));
                }
                anyhow::Ok(json!({ "message_id": id, "total": total, "readers": readers }))
            }
            .await;
            match result {
                Ok(v) => {
                    let text = v.to_string();
                    let _ = qt.queue(move |mut this| {
                        this.as_mut()
                            .set_message_readers_json(QString::from(text.as_str()))
                    });
                }
                Err(e) => tracing::warn!("read receipts unavailable: {}", short_error(&e)),
            }
        });
    }

    /// Show Teams' in-app toast.
    fn toast(mut self: Pin<&mut Self>, text: &str, intent: &str) {
        let id = chrono::Utc::now().timestamp_millis();
        let v = json!({ "id": id, "text": text, "intent": intent }).to_string();
        self.as_mut().set_toast_json(QString::from(v.as_str()));
    }

    pub fn forward_message(
        self: Pin<&mut Self>,
        message_id: &QString,
        targets_json: &QString,
        note: &QString,
    ) {
        let source = self.chat_of(&message_id.to_string());
        let id = message_id.to_string();
        let note = note.to_string();
        let targets: Vec<serde_json::Value> =
            serde_json::from_str(&targets_json.to_string()).unwrap_or_default();
        let group_chats = group_chat_ids(&self.rust().chats_json.to_string());
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                let target = picked_conversation(&client, &targets, &group_chats).await?;
                let note_html = if note.trim().is_empty() {
                    String::new()
                } else {
                    api::outbox::plain_html(&note)
                };
                api::msgactions::forward(
                    &client,
                    &source,
                    std::slice::from_ref(&id),
                    &target,
                    &note_html,
                )
                .await
            }
            .await;
            let _ = qt.queue(move |mut this| match result {
                Ok(_) => this.as_mut().toast("Message forwarded", "success"),
                Err(e) => {
                    tracing::warn!("forward failed: {}", short_error(&e));
                    this.as_mut().toast("Failed to forward", "error");
                }
            });
        });
    }

    pub fn report_message(mut self: Pin<&mut Self>, message_id: &QString, comment: &QString) {
        let (chat_id, id, comment) = (
            self.chat_of(&message_id.to_string()),
            message_id.to_string(),
            comment.to_string(),
        );
        self.as_mut().set_report_result(QString::from("sending"));
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                api::msgactions::report_security(&client, &chat_id, &id, &comment).await
            }
            .await;
            if let Err(e) = &result {
                tracing::warn!("report failed: {}", short_error(e));
            }
            let _ = qt.queue(move |mut this| {
                this.as_mut()
                    .set_report_result(QString::from(if result.is_ok() { "ok" } else { "error" }))
            });
        });
    }

    pub fn report_meeting(self: Pin<&mut Self>, comment: &QString, reported_json: &QString) {
        let thread = self.rust().call_thread_id.to_string();
        self.send_meeting_report(thread, None, comment.to_string(), reported_json.to_string());
    }

    pub fn set_work_location_today(mut self: Pin<&mut Self>, location: &QString) {
        let location = location.to_string();
        let before = self.rust().my_work_location.clone();
        self.as_mut().set_my_work_location(QString::from(location.as_str()));
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let http = reqwest::Client::new();
            let loc = (!location.is_empty()).then_some(location.as_str());
            if let Err(e) = teams_cli::api::presence::set_work_location(&http, loc).await {
                tracing::warn!("set work location failed: {}", short_error(&e));
                let _ = qt.queue(move |mut this| this.as_mut().set_my_work_location(before));
            }
        });
    }

    pub fn report_meeting_chat(
        self: Pin<&mut Self>,
        thread: &QString,
        ical_uid: &QString,
        comment: &QString,
        reported_json: &QString,
    ) {
        self.send_meeting_report(
            thread.to_string(),
            Some(ical_uid.to_string()),
            comment.to_string(),
            reported_json.to_string(),
        );
    }

    /// Send a meeting's security report: the call's (its id and meeting)
    /// when `chat_ical` is None, else a meeting chat's.
    fn send_meeting_report(mut self: Pin<&mut Self>, thread: String, chat_ical: Option<String>, comment: String, reported_json: String) {
        let reported: Vec<String> = serde_json::from_str(&reported_json).unwrap_or_default();
        self.as_mut().set_report_result(QString::from("sending"));
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let (call_id, ical) = match chat_ical {
                Some(ical) => (String::new(), ical),
                None => match call_slot().lock().await.outgoing.as_ref() {
                    Some(c) => (c.call_id().to_string(), c.meeting_info().map(|i| i.ical_uid).unwrap_or_default()),
                    None => (String::new(), String::new()),
                },
            };
            let result = async {
                let client = TeamsClient::new().await?;
                api::msgactions::report_meeting(&client, &thread, &call_id, &ical, &reported, &comment).await
            }
            .await;
            if let Err(e) = &result {
                tracing::warn!("meeting report failed: {}", short_error(e));
            }
            let _ = qt.queue(move |mut this| {
                this.as_mut()
                    .set_report_result(QString::from(if result.is_ok() { "ok" } else { "error" }))
            });
        });
    }

    pub fn translate_message(mut self: Pin<&mut Self>, message_id: &QString, on: bool) {
        let (chat_id, id) = (
            self.chat_of(&message_id.to_string()),
            message_id.to_string(),
        );
        let key = (chat_id.clone(), id.clone());
        // See original only hides the translation; Translate re-shows a
        // cached one (Teams' TranslationJob).
        {
            let mut t = translations().lock().unwrap();
            if let Some(entry) = t.get_mut(&key) {
                entry.1 = on;
                drop(t);
                self.as_mut().refresh_lies();
                return;
            }
        }
        if !on {
            return;
        }
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                // The user's language: the UI locale's language.
                let lang = std::env::var("LANG")
                    .ok()
                    .and_then(|l| l.split(['_', '.', '-']).next().map(str::to_string))
                    .filter(|l| !l.is_empty() && l != "C" && l != "POSIX")
                    .unwrap_or_else(|| "en".into());
                api::msgactions::translate(&client, &chat_id, &id, &lang).await
            }
            .await;
            // Done shows the translation; a failure shows Teams' "Failed to
            // translate" by the time; "not needed" changes nothing.
            let tr = match result {
                Ok(tr) => tr,
                Err(e) => {
                    tracing::warn!("translation failed: {}", short_error(&e));
                    api::msgactions::Translation {
                        status: "UnknownError".into(),
                        ..Default::default()
                    }
                }
            };
            let _ = qt.queue(move |mut this| {
                if tr.status != "TranslationNotNeeded" {
                    translations().lock().unwrap().insert(key, (tr, true));
                    this.as_mut().refresh_lies();
                }
            });
        });
    }

    pub fn set_next_importance(mut self: Pin<&mut Self>, importance: &QString) {
        let v = importance.to_string();
        self.as_mut().rust_mut().next_importance = if v == "high" || v == "urgent" {
            v
        } else {
            String::new()
        };
    }

    pub fn set_next_post(mut self: Pin<&mut Self>, post_json: &QString) {
        self.as_mut().rust_mut().next_post = NextPost::from_json(&post_json.to_string());
    }

    /// Put the post composer's fields on a new channel post.
    fn apply_next_post(mut self: Pin<&mut Self>, o: &mut api::outbox::Outgoing) {
        let Some(p) = self.as_mut().rust_mut().next_post.take() else { return };
        if !o.conversation_id.ends_with("@thread.tacv2") || o.conversation_id.contains(";messageid=") {
            return;
        }
        o.subject = p.subject.trim().chars().take(250).collect();
        o.threads_layout = p.threads;
        if !p.threads && !p.theme.is_empty() && p.theme.parse::<u8>().is_ok_and(|t| t < 12) {
            o.title = p.title.trim().chars().take(44).collect();
            o.banner_theme = Some(p.theme);
            if !p.image.is_empty() {
                o.banner_image = Some(api::outbox::BannerImage {
                    path: p.image,
                    width: p.image_w,
                    height: p.image_h,
                    ..Default::default()
                });
            }
        }
    }

    /// Send `o`: an announcement's picture goes to AMS first (readable in
    /// the channel), as Teams uploads it before posting.
    fn submit_outgoing(self: Pin<&mut Self>, mut o: api::outbox::Outgoing) {
        let Some(img) = o.banner_image.clone().filter(|i| i.id.is_empty()) else {
            let _rt = runtime().enter();
            outbox().submit(o);
            return;
        };
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                let base = client.ams_url().context("No media store address")?;
                let bytes = std::fs::read(&img.path).context("Reading the banner picture")?;
                let id = client.ams_upload_image(&o.conversation_id, bytes, "image.png").await?;
                anyhow::Ok((format!("{base}/v1/objects/{id}/views/imgpsh_fullsize"), id))
            }
            .await;
            let _ = qt.queue(move |mut this| match result {
                Ok((src, id)) => {
                    if let Some(i) = o.banner_image.as_mut() {
                        i.src = src;
                        i.id = id;
                    }
                    let _rt = runtime().enter();
                    outbox().submit(o);
                }
                Err(e) => this.as_mut().set_status_text(QString::from(
                    format!("Couldn't upload the picture: {}", short_error(&e)).as_str(),
                )),
            });
        });
    }

    pub fn set_reply_quote(mut self: Pin<&mut Self>, quote_json: &QString) {
        self.as_mut().rust_mut().reply_quote = serde_json::from_str(&quote_json.to_string()).ok();
    }

    /// Redraw the open chat's messages being sent over its last timeline.
    fn refresh_lies(mut self: Pin<&mut Self>) {
        self.as_mut().refresh_thread_windows();
        let chat_id = self.rust().current_chat_id.to_string();
        if chat_id.is_empty() {
            return;
        }
        // A chat whose timeline could not load still shows what is being sent.
        let timeline = server_timelines()
            .lock()
            .unwrap()
            .get(&chat_id)
            .cloned()
            .unwrap_or_default();
        let Ok(json) = serde_json::to_string(&with_lies(&chat_id, timeline)) else {
            return;
        };
        if self.rust().messages_json.to_string() != json {
            self.as_mut()
                .set_messages_json(QString::from(json.as_str()));
        }
    }

    /// Retry a failed message (Teams: same clientmessageid, sent again).
    pub fn retry_failed_message(self: Pin<&mut Self>, client_message_id: &QString) {
        let chat_id = self.rust().current_chat_id.to_string();
        let last = server_timelines()
            .lock()
            .unwrap()
            .get(&chat_id)
            .and_then(|t| t.iter().filter_map(|m| m.id.parse::<i64>().ok()).max());
        let _rt = runtime().enter();
        outbox().retry(&client_message_id.to_string(), last);
    }

    /// Delete a failed message (Teams: local only).
    pub fn delete_failed_message(self: Pin<&mut Self>, client_message_id: &QString) {
        outbox().delete(&client_message_id.to_string());
    }

    /// Scrolled to the top: load the page before (Teams pages back with the
    /// syncState of the page's backwardLink), then show the merged timeline.
    pub fn load_older_messages(mut self: Pin<&mut Self>) {
        let chat_id = self.rust().current_chat_id.to_string();
        let token = older_pages()
            .lock()
            .unwrap()
            .get(&chat_id)
            .and_then(|e| e.1.clone());
        let Some(token) = token else { return };
        if self.rust().messages_loading_older {
            return;
        }
        self.as_mut().set_messages_loading_older(true);
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                api::messages::read_timeline_page(
                    &client,
                    &chat_id,
                    api::messages::PAGE_SIZE,
                    Some(&token),
                )
                .await
            }
            .await;
            match result {
                Ok(page) => {
                    if let Some(entry) = older_pages().lock().unwrap().get_mut(&chat_id) {
                        entry.0 = api::messages::merge_pages(
                            &page.messages,
                            std::mem::take(&mut entry.0),
                        );
                        entry.1 = page.older;
                    }
                    let _ = qt.queue(|mut this| this.as_mut().reload_messages());
                }
                Err(e) => {
                    tracing::warn!("older messages: {}", short_error(&e));
                    let _ = qt.queue(|mut this| this.as_mut().set_messages_loading_older(false));
                }
            }
        });
    }

    fn reload_messages(self: Pin<&mut Self>) {
        let chat_id = self.rust().current_chat_id.to_string();
        if chat_id.is_empty() {
            return;
        }
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let wanted = chat_id.clone();
            let result = load_messages(chat_id).await;
            tracing::info!(ok = result.is_ok(), "messages loaded");
            let _ = qt.queue(move |mut this| {
                // Ignore a late answer for a chat the user has already left.
                if this.rust().current_chat_id.to_string() != wanted {
                    return;
                }
                match result {
                    Ok((json, last_id, has_older)) => {
                        let banner = {
                            let b = pinned_banner().lock().unwrap();
                            if b.0 == wanted && !b.1.is_null() {
                                b.1.to_string()
                            } else {
                                String::new()
                            }
                        };
                        this.as_mut()
                            .set_pinned_json(QString::from(banner.as_str()));
                        this.as_mut().set_messages_has_older(has_older);
                        this.as_mut().set_messages_loading_older(false);
                        this.as_mut()
                            .set_messages_json(QString::from(json.as_str()));
                        this.as_mut().rust_mut().newest_message_id = last_id;
                        this.as_mut().mark_current_read();
                    }
                    Err(e) => this
                        .as_mut()
                        .set_status_text(QString::from(short_error(&e).as_str())),
                }
            });
        });
    }

    /// Joined teams with their channels, for the chat pane.
    fn load_teams(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                // Teams' own list: which channels you show, unread, New.
                let teams = api::teams::list_teams_csa(&client).await?;
                Ok::<_, anyhow::Error>((client, teams))
            }
            .await;
            match result {
                Ok((client, teams)) => {
                    let text = serde_json::to_string(&teams).unwrap_or_else(|_| "[]".into());
                    // A team picture whose ETag changed is fetched again (as
                    // Teams asks for it by ETag).
                    let changed: Vec<String> = teams
                        .iter()
                        .filter(|t| team_picture_changed(&t.id, &t.picture_etag))
                        .map(|t| format!("team:{}", t.id))
                        .collect();
                    let _ = qt.queue(move |mut this| {
                        for id in &changed {
                            this.as_mut().forget_photos(id);
                        }
                        // Layouts the chat service told us the list lacks.
                        let fixes = this.rust().channel_layouts.clone();
                        let mut v: serde_json::Value = serde_json::from_str(&text).unwrap_or_default();
                        for t in v.as_array_mut().into_iter().flatten() {
                            for c in t["channels"].as_array_mut().into_iter().flatten() {
                                if let Some(l) = c["id"].as_str().and_then(|id| fixes.get(id)) {
                                    c["layout"] = json!(l);
                                }
                            }
                        }
                        this.as_mut().set_teams_json(QString::from(v.to_string().as_str()))
                    });
                    // Every team's tags: the @ picker offers them, and a
                    // mention of a tag you are in mentions you (as Teams'
                    // currentUserTagIds).
                    let mut all = serde_json::Map::new();
                    for t in teams.iter().filter(|t| !t.thread_id.is_empty()) {
                        match api::teams::team_tags(&client, &t.thread_id).await {
                            Ok(tags) => {
                                all.insert(t.thread_id.clone(), json!(tags));
                            }
                            Err(e) => tracing::warn!("tags of {}: {}", t.name, short_error(&e)),
                        }
                    }
                    let text = serde_json::Value::Object(all).to_string();
                    let _ = qt.queue(move |mut this| this.as_mut().set_team_tags_json(QString::from(text.as_str())));
                }
                Err(e) => tracing::warn!("teams failed: {}", short_error(&e)),
            }
        });
    }

    /// Chats Teams considers unread (newer messages than our read horizon).
    fn load_server_unread(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                api::messages::unread_chat_ids(&client).await
            }
            .await;
            match result {
                Ok(ids) => {
                    let _ = qt.queue(move |mut this| {
                        let current = this.rust().current_chat_id.to_string();
                        for id in ids.into_iter().filter(|i| *i != current) {
                            this.as_mut().rust_mut().unread.insert(id);
                        }
                        this.as_mut().publish_chats();
                    });
                }
                Err(e) => tracing::warn!("unread state failed: {}", short_error(&e)),
            }
        });
    }

    /// Mark the open chat read up to its newest message, if the window has
    /// focus and we have not already done so.
    pub fn mark_current_read(mut self: Pin<&mut Self>) {
        let chat_id = self.rust().current_chat_id.to_string();
        let Some(last) = self.rust().newest_message_id.clone() else {
            return;
        };
        if chat_id.is_empty() || !self.rust().window_active {
            return;
        }
        if self.rust().marked_read.get(&chat_id) == Some(&last.0) {
            return;
        }
        self.as_mut()
            .rust_mut()
            .marked_read
            .insert(chat_id.clone(), last.0.clone());
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                api::messages::mark_read(&client, &chat_id, &last.0, &last.1).await
            }
            .await;
            match result {
                Ok(()) => tracing::info!("marked read"),
                Err(e) => tracing::warn!("mark read failed: {}", short_error(&e)),
            }
        });
    }

    /// A custom emoji's picture as a file URL, fetched (and cached) on
    /// first use; "" until then (emoticonsVersion changes when it lands).
    fn custom_emoji_picture(self: Pin<&mut Self>, document_id: &str) -> QString {
        let key = format!("custom:{document_id}");
        if let Some(f) = emoticon_files().lock().unwrap().get(&key) {
            return QString::from(f.as_str());
        }
        if let Some(path) = custom_emoji_cached(document_id) {
            let url = format!("file://{}", path.display());
            emoticon_files().lock().unwrap().insert(key, url.clone());
            return QString::from(url.as_str());
        }
        emoticon_files()
            .lock()
            .unwrap()
            .insert(key.clone(), String::new());
        let doc = document_id.to_string();
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                custom_emoji_file(&client, &doc).await
            }
            .await;
            match result {
                Ok(path) => {
                    emoticon_files()
                        .lock()
                        .unwrap()
                        .insert(key, format!("file://{}", path.display()));
                    let _ = qt.queue(|mut this| {
                        let v = this.rust().emoticons_version + 1;
                        this.as_mut().set_emoticons_version(v);
                    });
                }
                Err(e) => tracing::warn!("custom emoji picture failed: {}", short_error(&e)),
            }
        });
        QString::default()
    }

    pub fn emoticon_unicode(&self, key: &QString) -> QString {
        emoticon_catalog()
            .read()
            .unwrap()
            .as_ref()
            .map(|c| QString::from(c.unicode(&key.to_string()).as_str()))
            .unwrap_or_default()
    }

    pub fn emoticon_url(self: Pin<&mut Self>, key: &QString, size: i32) -> QString {
        // A custom emoji ("{name};{documentId}"): its cached picture.
        if let Some(e) = api::custom_emoji::CustomEmoji::from_id(&key.to_string()) {
            return self.custom_emoji_picture(&e.document_id);
        }
        let catalog = emoticon_catalog().read().unwrap().clone();
        let qt = self.qt_thread();
        let Some(catalog) = catalog else {
            static LOADING: AtomicBool = AtomicBool::new(false);
            if !LOADING.swap(true, Ordering::SeqCst) {
                runtime().spawn(async move {
                    match api::emoticons::load_catalog(&cache_base(), "en-us").await {
                        Ok(c) => {
                            *emoticon_catalog().write().unwrap() = Some(std::sync::Arc::new(c));
                            let _ = qt.queue(|mut this| {
                                let v = this.rust().emoticons_version + 1;
                                this.as_mut().set_emoticons_version(v);
                            });
                        }
                        Err(e) => {
                            tracing::warn!("emoticons unavailable: {}", short_error(&e));
                            LOADING.store(false, Ordering::SeqCst);
                        }
                    }
                });
            }
            return QString::default();
        };
        let Some(url) = catalog.image_url(&key.to_string(), size.max(16) as u32, false) else {
            return QString::default();
        };
        if let Some(f) = emoticon_files().lock().unwrap().get(&url) {
            return QString::from(f.as_str());
        }
        emoticon_files()
            .lock()
            .unwrap()
            .insert(url.clone(), String::new());
        runtime().spawn(async move {
            match api::emoticons::image_file(&url, &cache_base()).await {
                Ok(path) => {
                    emoticon_files()
                        .lock()
                        .unwrap()
                        .insert(url, format!("file://{}", path.display()));
                    let _ = qt.queue(|mut this| {
                        let v = this.rust().emoticons_version + 1;
                        this.as_mut().set_emoticons_version(v);
                    });
                }
                Err(e) => tracing::warn!("emoticon image failed: {}", short_error(&e)),
            }
        });
        QString::default()
    }

    pub fn set_noise_suppression(self: Pin<&mut Self>, on: bool) {
        self.set_setting(&QString::from("noiseSuppression"), &QString::from(if on { "on" } else { "off" }));
        teams_cli::calling::apm::set_noise_level(if on {
            teams_cli::calling::apm::NoiseLevel::High
        } else {
            teams_cli::calling::apm::NoiseLevel::Off
        });
    }

    pub fn set_taskbar_badge(&self, count: i32, kind: &QString) {
        if let Ok(k) = std::ffi::CString::new(kind.to_string()) {
            // SAFETY: a NUL-terminated string read during the call, on the
            // GUI thread (QML calls this).
            unsafe { ost_set_taskbar_badge(count, k.as_ptr()) };
        }
        runtime().spawn(crate::launcher_badge::update(i64::from(count)));
    }

    pub fn set_music_mode(mut self: Pin<&mut Self>, on: bool, echo_cancellation: bool) {
        let v = |b: bool| QString::from(if b { "on" } else { "off" });
        self.as_mut().set_setting(&QString::from("musicMode"), &v(on));
        self.as_mut().set_setting(&QString::from("musicModeEcho"), &v(echo_cancellation));
        tracing::info!(on, echo_cancellation, "music mode");
        teams_cli::calling::apm::set_music_mode(on, echo_cancellation);
    }

    pub fn ubar_arrange(
        &self,
        facts: &QString,
        widths: &QString,
        divider: f64,
        available: f64,
    ) -> QString {
        use teams_cli::calling::ubar;
        let facts: ubar::Facts = serde_json::from_str(&facts.to_string()).unwrap_or_default();
        let widths: HashMap<String, f64> = serde_json::from_str(&widths.to_string()).unwrap_or_default();
        let arranged = ubar::arrange(
            &facts,
            &|n| widths.get(n).copied().unwrap_or(56.0),
            divider,
            available,
        );
        QString::from(serde_json::to_string(&arranged).unwrap_or_default().as_str())
    }

    pub fn card_image(self: Pin<&mut Self>, url: &QString) -> QString {
        let url = url.to_string();
        if url.starts_with("data:") {
            return QString::from(url.as_str());
        }
        if !url.starts_with("https://") && !url.starts_with("http://") {
            return QString::default();
        }
        if let Some(f) = emoticon_files().lock().unwrap().get(&url) {
            return QString::from(f.as_str());
        }
        emoticon_files()
            .lock()
            .unwrap()
            .insert(url.clone(), String::new());
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let client = TeamsClient::new().await.ok();
            match api::emoticons::remote_image_file(&url, &cache_base(), client.as_ref()).await {
                Ok(path) => {
                    emoticon_files()
                        .lock()
                        .unwrap()
                        .insert(url, format!("file://{}", path.display()));
                    let _ = qt.queue(|mut this| {
                        let v = this.rust().emoticons_version + 1;
                        this.as_mut().set_emoticons_version(v);
                    });
                }
                Err(e) => tracing::warn!("card image failed: {}", short_error(&e)),
            }
        });
        QString::default()
    }

    pub fn emoticon_category_icon(self: Pin<&mut Self>, category_id: &QString) -> QString {
        let id: String = category_id
            .to_string()
            .chars()
            .filter(|c| c.is_ascii_alphanumeric() || *c == '_' || *c == '-')
            .collect();
        if id.is_empty() {
            return QString::default();
        }
        let url = format!(
            "{}/evergreen-assets/personal-expressions/v2/assets/categories/{id}/thumbnail.svg",
            api::emoticons::STATICS
        );
        if let Some(f) = emoticon_files().lock().unwrap().get(&url) {
            return QString::from(f.as_str());
        }
        emoticon_files()
            .lock()
            .unwrap()
            .insert(url.clone(), String::new());
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let file = cache_base()
                .join("emoticons")
                .join(format!("category-{id}.svg"));
            let result = async {
                if !file.exists() {
                    let bytes = reqwest::get(&url)
                        .await?
                        .error_for_status()?
                        .bytes()
                        .await?;
                    std::fs::create_dir_all(file.parent().unwrap())?;
                    std::fs::write(&file, &bytes)?;
                }
                anyhow::Ok(())
            }
            .await;
            match result {
                Ok(()) => {
                    emoticon_files()
                        .lock()
                        .unwrap()
                        .insert(url, format!("file://{}", file.display()));
                    let _ = qt.queue(|mut this| {
                        let v = this.rust().emoticons_version + 1;
                        this.as_mut().set_emoticons_version(v);
                    });
                }
                Err(e) => tracing::warn!("emoticon category icon failed: {}", short_error(&e)),
            }
        });
        QString::default()
    }

    pub fn emoticon_catalog_json(self: Pin<&mut Self>) -> QString {
        let Some(c) = emoticon_catalog().read().unwrap().clone() else {
            // Starts the download; emoticonsVersion changes when it lands.
            let _ = self.emoticon_url(&QString::from("yes"), 20);
            return QString::default();
        };
        let list: Vec<_> = c
            .categories
            .iter()
            .map(|cat| {
                json!({
                    "id": cat.id,
                    "title": cat.title,
                    "emoticons": cat.emoticons.iter().map(|e| json!({"id": e.id, "description": e.description, "diverse": e.diverse, "keywords": e.keywords, "shortcuts": e.shortcuts})).collect::<Vec<_>>(),
                })
            })
            .collect();
        QString::from(serde_json::to_string(&list).unwrap_or_default().as_str())
    }

    /// Load the Recent emoticons (roamed, else Teams' defaults).
    fn load_recent_reactions(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let prefs = match TeamsClient::new().await {
                Ok(c) => api::emoticons::reaction_prefs(&c).await,
                Err(_) => api::emoticons::ReactionPrefs::from_properties(&serde_json::Value::Null),
            };
            let recent = serde_json::to_string(&prefs.recent).unwrap_or_default();
            let quick = serde_json::to_string(&prefs.quick).unwrap_or_default();
            let _ = qt.queue(move |mut this| {
                this.as_mut()
                    .set_recent_reactions_json(QString::from(recent.as_str()));
                this.as_mut()
                    .set_quick_reactions_json(QString::from(quick.as_str()));
                this.as_mut().set_skin_tone(prefs.tone as i32);
            });
            if let Ok(c) = TeamsClient::new().await
                && let Ok(settings) = api::preferences::personal_settings(&c).await
            {
                let video = api::preferences::header_call_is_video(&settings);
                let _ = qt.queue(move |mut this| this.as_mut().set_header_call_video(video));
            }
            if let Ok(c) = TeamsClient::new().await
                && let Ok(bottom) = api::channels::new_posts_at_bottom(&c).await
            {
                let _ = qt.queue(move |mut this| this.as_mut().set_channel_posts_at_top(!bottom));
            }
        });
    }

    pub fn emoticon_in_tone(&self, key: &QString, tone: i32) -> QString {
        let out = api::emoticons::with_tone(
            emoticon_catalog().read().unwrap().as_deref(),
            &key.to_string(),
            tone.clamp(0, 5) as u8,
        );
        QString::from(out.as_str())
    }

    pub fn save_reaction_prefs(mut self: Pin<&mut Self>, slots_json: &QString, tone: i32) {
        let slots: Vec<String> = serde_json::from_str(&slots_json.to_string()).unwrap_or_default();
        let tone = tone.clamp(0, 5) as u8;
        let tone_changed = tone as i32 != self.rust().skin_tone;
        self.as_mut()
            .set_reaction_prefs_result(QString::from("saving"));
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                api::emoticons::set_default_reactions(&client, &slots).await?;
                if tone_changed {
                    api::emoticons::set_skin_tone(&client, tone).await?;
                }
                anyhow::Ok(())
            }
            .await;
            let _ = qt.queue(move |mut this| match result {
                Ok(()) => {
                    let quick = serde_json::to_string(&slots).unwrap_or_default();
                    this.as_mut()
                        .set_quick_reactions_json(QString::from(quick.as_str()));
                    this.as_mut().set_skin_tone(tone as i32);
                    this.as_mut().set_reaction_prefs_result(QString::from("ok"));
                }
                Err(e) => {
                    tracing::warn!("reaction preferences not saved: {}", short_error(&e));
                    this.as_mut()
                        .set_reaction_prefs_result(QString::from("error"));
                }
            });
        });
    }

    pub fn emoticon_toned(&self, key: &QString) -> QString {
        let tone = self.rust().skin_tone.clamp(0, 5) as u8;
        let out = api::emoticons::with_tone(
            emoticon_catalog().read().unwrap().as_deref(),
            &key.to_string(),
            tone,
        );
        QString::from(out.as_str())
    }

    pub fn emoticon_name(&self, key: &QString) -> QString {
        let key = key.to_string();
        // A custom emoji's name is its shortcut (763654 `vt`).
        if let Some(e) = api::custom_emoji::CustomEmoji::from_id(&key) {
            return QString::from(e.shortcut.as_str());
        }
        let name = match emoticon_catalog().read().unwrap().as_ref() {
            Some(c) => c.reaction_name(&key),
            None => api::emoticons::parse_key(&key).0,
        };
        QString::from(name.as_str())
    }

    pub fn emoticon_size(&self, named: &QString, hidpi: bool) -> i32 {
        api::emoticons::asset_size(&named.to_string(), hidpi) as i32
    }

    /// Forget a picture (memory and disk) so the next photo_for fetches it
    /// again, and tell the views (a team picture changed from OST).
    fn forget_photos(mut self: Pin<&mut Self>, id: &str) {
        let prefix = format!("{id}\u{1f}");
        self.as_mut().rust_mut().photos.retain(|k, _| !k.starts_with(&prefix));
        if let Some((owner, oid)) = photo_target(id, None)
            && let Some(dir) = photo_dir()
            && let Ok(entries) = std::fs::read_dir(&dir)
        {
            let lead = format!(
                "{}-{oid}-",
                match owner {
                    api::directory::PhotoOwner::Team => "team",
                    api::directory::PhotoOwner::Named => "named",
                    api::directory::PhotoOwner::User => "user",
                }
            );
            for e in entries.flatten() {
                if e.file_name().to_string_lossy().starts_with(&lead) {
                    let _ = std::fs::remove_file(e.path());
                }
            }
        }
        self.as_mut().photo_ready(QString::from(id));
    }

    pub fn photo_for(mut self: Pin<&mut Self>, id: &QString, name: &QString) -> QString {
        let id = id.to_string();
        let name = name.to_string();
        let id_key = format!("{id}\u{1f}{name}");
        if let Some(known) = self.rust().photos.get(&id_key) {
            return QString::from(known.as_deref().unwrap_or(""));
        }
        let my_oid = self
            .rust()
            .my_mri
            .as_deref()
            .and_then(|m| m.strip_prefix("8:orgid:"))
            .map(str::to_string)
            .or_else(|| {
                teams_cli::config::Config::load()
                    .ok()
                    .and_then(|c| c.object_id())
            });
        let Some((owner, oid)) = photo_target(&id, my_oid.as_deref()) else {
            self.as_mut().rust_mut().photos.insert(id_key, None);
            return QString::default();
        };
        // The name is part of the key: Teams draws initials pictures from it.
        let name_hash = name.bytes().fold(0x811c9dc5u32, |h, b| {
            (h ^ b as u32).wrapping_mul(0x01000193)
        });
        let key = format!(
            "{}-{oid}-{name_hash:08x}",
            match owner {
                api::directory::PhotoOwner::Team => "team",
                api::directory::PhotoOwner::Named => "named",
                api::directory::PhotoOwner::User => "user",
            }
        );
        let (cached, fresh) = photo_from_disk(&key);
        if let Some(c) = &cached {
            self.as_mut()
                .rust_mut()
                .photos
                .insert(id_key.clone(), c.clone());
        }
        if !fresh
            && self
                .as_mut()
                .rust_mut()
                .photo_fetching
                .insert(id_key.clone())
        {
            let qt = self.qt_thread();
            let id2 = id.clone();
            runtime().spawn(async move {
                let result = fetch_photo(owner, &oid, &name, &key).await;
                let _ = qt.queue(move |mut this| {
                    this.as_mut().rust_mut().photo_fetching.remove(&id_key);
                    match result {
                        Ok(url) => {
                            this.as_mut().rust_mut().photos.insert(id_key, url);
                            this.as_mut().photo_ready(QString::from(id2.as_str()));
                        }
                        Err(e) => tracing::debug!("photo unavailable: {}", short_error(&e)),
                    }
                });
            });
        }
        QString::from(cached.flatten().as_deref().unwrap_or(""))
    }

    pub fn file_thumbnail(mut self: Pin<&mut Self>, url: &QString) -> QString {
        let url = url.to_string();
        if let Some(known) = self.rust().thumbnails.get(&url) {
            return QString::from(known.as_deref().unwrap_or(""));
        }
        if url.is_empty() || !self.as_mut().rust_mut().thumbnail_fetching.insert(url.clone()) {
            return QString::default();
        }
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                let Some(bytes) = api::files::thumbnail(&client, &url).await? else { return anyhow::Ok(None) };
                let dir = photo_dir().ok_or_else(|| anyhow::anyhow!("No cache directory"))?.with_file_name("thumbnails");
                std::fs::create_dir_all(&dir)?;
                let name = url.bytes().fold(0xcbf29ce484222325u64, |h, b| (h ^ b as u64).wrapping_mul(0x100000001b3));
                let path = dir.join(format!("{name:016x}.jpg"));
                write_private(&path, &bytes)?;
                anyhow::Ok(Some(format!("file://{}", path.display())))
            }
            .await;
            let _ = qt.queue(move |mut this| {
                this.as_mut().rust_mut().thumbnail_fetching.remove(&url);
                let found = result.unwrap_or_else(|e| {
                    tracing::debug!("thumbnail unavailable: {}", short_error(&e));
                    None
                });
                this.as_mut().rust_mut().thumbnails.insert(url.clone(), found);
                this.as_mut().thumbnail_ready(QString::from(url.as_str()));
            });
        });
        QString::default()
    }

    fn drafts_mut(self: Pin<&mut Self>) -> &mut HashMap<String, (String, u64)> {
        self.rust_mut()
            .get_mut()
            .drafts
            .get_or_insert_with(load_drafts)
    }

    pub fn set_draft(mut self: Pin<&mut Self>, chat_id: &QString, text: &QString) {
        let id = chat_id.to_string();
        let text = text.to_string();
        if id.is_empty() {
            return;
        }
        let drafts = self.as_mut().drafts_mut();
        let changed = if text.trim().is_empty() {
            drafts.remove(&id).is_some()
        } else if drafts.get(&id).map(|d| &d.0) != Some(&text) {
            let now = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_millis() as u64)
                .unwrap_or_default();
            drafts.insert(id, (text, now));
            true
        } else {
            false
        };
        if changed {
            if let Err(e) = save_drafts(self.as_mut().drafts_mut()) {
                tracing::warn!("saving drafts failed: {}", short_error(&e));
            }
            self.as_mut().publish_drafts();
        }
    }

    pub fn draft_for(mut self: Pin<&mut Self>, chat_id: &QString) -> QString {
        let id = chat_id.to_string();
        let text = self
            .as_mut()
            .drafts_mut()
            .get(&id)
            .map(|d| d.0.clone())
            .unwrap_or_default();
        QString::from(text.as_str())
    }

    /// The drafts list for Quick views > Drafts, newest first.
    fn publish_drafts(mut self: Pin<&mut Self>) {
        let mut list: Vec<(String, String, u64)> = self
            .as_mut()
            .drafts_mut()
            .iter()
            .map(|(id, (text, t))| (id.clone(), text.clone(), *t))
            .collect();
        list.sort_by_key(|a| std::cmp::Reverse(a.2));
        let chats = &self.rust().chats;
        let json: Vec<serde_json::Value> = list
            .into_iter()
            .map(|(id, text, t)| {
                let chat = chats.iter().find(|c| c["id"].as_str() == Some(id.as_str()));
                json!({
                    "id": id,
                    "name": chat.and_then(|c| c["name"].as_str()).unwrap_or(""),
                    "peerMri": chat.and_then(|c| c["peerMri"].as_str()).unwrap_or(""),
                    "text": text,
                    "time": t,
                })
            })
            .collect();
        let text = serde_json::to_string(&json).unwrap_or_else(|_| "[]".into());
        self.as_mut().set_drafts_json(QString::from(text.as_str()));
    }

    pub fn load_activity(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                let items = api::activity::feed(&client, ACTIVITY_LIMIT).await?;
                // The badge counts what arrived since Activity was last
                // opened (the feed's read position), as in Teams; each
                // item's own bold state is separate.
                let seen = api::messages::my_read_horizon(&client, "48:notifications")
                    .await
                    .unwrap_or(None)
                    .unwrap_or(0);
                anyhow::Ok((items, seen))
            }
            .await;
            match result {
                Ok((items, seen)) => {
                    let unread = items
                        .iter()
                        .filter(|i| i.id.parse::<u64>().is_ok_and(|id| id > seen))
                        .count() as i32;
                    let json = serde_json::to_string(&items).unwrap_or_else(|_| "[]".into());
                    let _ = qt.queue(move |mut this| {
                        // Count first, so anything reacting to the feed sees it.
                        this.as_mut().set_activity_unread(unread);
                        this.as_mut()
                            .set_activity_json(QString::from(json.as_str()));
                    });
                }
                Err(e) => tracing::warn!("activity failed: {}", short_error(&e)),
            }
        });
    }

    pub fn mark_activity_read(mut self: Pin<&mut Self>) {
        let json = self.rust().activity_json.to_string();
        let Ok(mut items) = serde_json::from_str::<Vec<serde_json::Value>>(&json) else {
            return;
        };
        if self.rust().activity_unread == 0 {
            return;
        }
        // Teams clears the badge when Activity opens; the items stay bold
        // until each is opened, so only the count goes.
        self.as_mut().set_activity_unread(0);
        let newest = items
            .iter_mut()
            .filter_map(|i| i["id"].as_str().map(str::to_string))
            .max_by_key(|id| id.parse::<u64>().unwrap_or(0));
        let Some(newest) = newest else { return };
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                api::activity::mark_read(&client, &newest).await
            }
            .await;
            if let Err(e) = result {
                tracing::warn!("activity mark read failed: {}", short_error(&e));
            }
        });
    }

    pub fn mark_activity_item_read(mut self: Pin<&mut Self>, id: &QString) {
        let id = id.to_string();
        let json = self.rust().activity_json.to_string();
        let Ok(mut items) = serde_json::from_str::<Vec<serde_json::Value>>(&json) else {
            return;
        };
        let Some(item) = items
            .iter_mut()
            .find(|i| i["id"].as_str() == Some(id.as_str()))
        else {
            return;
        };
        if item["unread"] != json!(true) {
            return;
        }
        item["unread"] = json!(false);
        let text = serde_json::to_string(&items).unwrap_or_else(|_| "[]".into());
        self.as_mut()
            .set_activity_json(QString::from(text.as_str()));
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                api::activity::mark_item_read(&client, &id).await
            }
            .await;
            if let Err(e) = result {
                tracing::warn!("activity item read failed: {}", short_error(&e));
            }
        });
    }

    pub fn tenant_id(&self) -> QString {
        QString::from(
            teams_cli::config::Config::load()
                .ok()
                .and_then(|c| c.tenant_id())
                .unwrap_or_default()
                .as_str(),
        )
    }

    pub fn setting(self: Pin<&mut Self>, name: &QString) -> QString {
        let value = load_settings()
            .get(&name.to_string())
            .map(|v| match v {
                serde_json::Value::String(s) => s.clone(),
                other => other.to_string(),
            })
            .unwrap_or_default();
        QString::from(value.as_str())
    }

    pub fn set_setting(mut self: Pin<&mut Self>, name: &QString, value: &QString) {
        let name = name.to_string();
        let value = value.to_string();
        let mut map = load_settings();
        map.insert(name.clone(), serde_json::Value::String(value.clone()));
        if let Err(e) = save_settings(&map) {
            tracing::warn!("saving settings failed: {}", short_error(&e));
        }
        if name == "theme" {
            self.as_mut().set_theme_mode(QString::from(value.as_str()));
        }
        if name == "micDevice" || name == "speakerDevice" {
            apply_audio_devices(&map);
        }
        if name == "autoStart"
            && let Err(e) = set_autostart(value == "true")
        {
            tracing::warn!("auto-start: {}", short_error(&e));
        }
    }

    /// Which of Teams' engagement actions you've done.
    fn load_engagement(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async { api::engagement::load_completed_actions(&TeamsClient::new().await?).await }.await;
            match result {
                Ok(list) => {
                    let text = json!(list).to_string();
                    let _ = qt.queue(move |mut this| this.as_mut().set_esp_actions_json(QString::from(text.as_str())));
                }
                Err(e) => tracing::info!("engagement state: {}", short_error(&e)),
            }
        });
    }

    pub fn record_engagement_action(mut self: Pin<&mut Self>, action: &QString) {
        let action = action.to_string();
        let mut done: Vec<String> = serde_json::from_str(&self.rust().esp_actions_json.to_string()).unwrap_or_default();
        if done.contains(&action) {
            return;
        }
        done.push(action.clone());
        self.as_mut().set_esp_actions_json(QString::from(json!(done).to_string().as_str()));
        runtime().spawn(async move {
            let result = async { api::engagement::record_action(&TeamsClient::new().await?, &action).await }.await;
            if let Err(e) = result {
                tracing::warn!("engagement action {action}: {}", short_error(&e));
            }
        });
    }

    /// Your e-mail and organisation name, for the profile menu.
    fn load_profile(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                let me = api::whoami_data(&client).await?;
                let org = match client.graph_get("/organization?$select=displayName").await {
                    Ok(r) => r
                        .json::<serde_json::Value>()
                        .await
                        .ok()
                        .and_then(|v| {
                            v.pointer("/value/0/displayName")
                                .and_then(|n| n.as_str())
                                .map(str::to_string)
                        })
                        .unwrap_or_default(),
                    Err(_) => String::new(),
                };
                anyhow::Ok((me.mail.unwrap_or_default(), org))
            }
            .await;
            if let Ok((mail, org)) = result {
                let _ = qt.queue(move |mut this| {
                    this.as_mut().set_user_mail(QString::from(mail.as_str()));
                    this.as_mut().set_org_name(QString::from(org.as_str()));
                });
            }
        });
    }

    pub fn create_group_chat(
        mut self: Pin<&mut Self>,
        oids: &QString,
        topic: &QString,
        first_message: &QString,
    ) {
        let Some(me) = teams_cli::config::Config::load()
            .ok()
            .and_then(|c| c.object_id())
        else {
            return;
        };
        let mut members = vec![format!("8:orgid:{me}")];
        members.extend(
            oids.to_string()
                .split(',')
                .map(str::trim)
                .filter(|o| !o.is_empty())
                .map(|o| format!("8:orgid:{}", o.trim_start_matches("8:orgid:"))),
        );
        let (topic, text) = (topic.to_string(), first_message.to_string());
        self.as_mut().set_busy(true);
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                let id = api::create_group_chat(&client, &members, &topic).await?;
                if !text.trim().is_empty() {
                    api::send_message_with_client(&client, &id, &text).await?;
                }
                anyhow::Ok(id)
            }
            .await;
            let _ = qt.queue(move |mut this| {
                this.as_mut().set_busy(false);
                match result {
                    Ok(id) => {
                        tracing::info!("group chat created");
                        let name = if topic.trim().is_empty() {
                            "New group chat".to_string()
                        } else {
                            topic
                        };
                        this.as_mut().select_chat(
                            &QString::from(id.as_str()),
                            &QString::from(name.as_str()),
                        );
                        this.as_mut().reload_chats();
                    }
                    Err(e) => this
                        .as_mut()
                        .set_status_text(QString::from(short_error(&e).as_str())),
                }
            });
        });
    }

    pub fn store_load(mut self: Pin<&mut Self>) {
        if self.rust().store_busy {
            return;
        }
        self.as_mut().set_store_busy(true);
        let qt = self.qt_thread();
        runtime().spawn(async move {
            // Teams' Store home: its feed and header menus (the store
            // content doc over the ranked catalog).
            let result = async { api::store_content::store_home(&TeamsClient::new().await?).await }.await;
            let _ = qt.queue(move |mut this| {
                this.as_mut().set_store_busy(false);
                let text = match result {
                    Ok(home) => json!(home).to_string(),
                    Err(e) => json!({ "error": short_error(&e) }).to_string(),
                };
                this.as_mut().set_store_json(QString::from(text.as_str()));
            });
        });
    }

    pub fn app_permissions_load(mut self: Pin<&mut Self>, app_id: &QString) {
        let app = app_id.to_string();
        self.as_mut().set_app_permissions_json(QString::from(json!({ "app": app, "loading": true }).to_string().as_str()));
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async { api::app_details::definition(&TeamsClient::new().await?, &app).await }.await;
            let _ = qt.queue(move |mut this| {
                let v = match result {
                    Ok(def) => {
                        let pre = api::app_details::device_permissions_preapproved(&app);
                        let saved = this.as_mut().saved_app_permissions();
                        let items: Vec<serde_json::Value> = api::app_details::device_permissions(&def)
                            .into_iter()
                            .map(|d| {
                                let on = saved.pointer(&format!("/{}/{}", app.to_lowercase(), d.kind)).and_then(|b| b.as_bool()).unwrap_or(pre);
                                json!({ "kind": d.kind, "title": d.title, "subtitle": d.subtitle, "on": on })
                            })
                            .collect();
                        json!({
                            "app": app,
                            "name": def.get("name").and_then(|n| n.as_str()).unwrap_or_default(),
                            "icon": def.get("largeImageUrl").and_then(|n| n.as_str()).unwrap_or_default(),
                            "preapproved": pre,
                            "items": items,
                        })
                    }
                    Err(e) => json!({ "app": app, "error": short_error(&e) }),
                };
                this.as_mut().set_app_permissions_json(QString::from(v.to_string().as_str()));
            });
        });
    }

    /// App permissions changed on this device: {appId: {kind: bool}}.
    fn saved_app_permissions(self: Pin<&mut Self>) -> serde_json::Value {
        let raw = self.setting(&QString::from("appDevicePermissions")).to_string();
        serde_json::from_str(&raw).unwrap_or_else(|_| json!({}))
    }

    pub fn app_permission(mut self: Pin<&mut Self>, app_id: &QString, kind: &QString) -> bool {
        let (app, kind) = (app_id.to_string().to_lowercase(), kind.to_string());
        let saved = self.as_mut().saved_app_permissions();
        saved
            .pointer(&format!("/{app}/{kind}"))
            .and_then(|b| b.as_bool())
            .unwrap_or_else(|| api::app_details::device_permissions_preapproved(&app))
    }

    pub fn set_app_permission(mut self: Pin<&mut Self>, app_id: &QString, kind: &QString, on: bool) {
        let (app, kind) = (app_id.to_string().to_lowercase(), kind.to_string());
        let mut saved = self.as_mut().saved_app_permissions();
        if !saved.get(&app).is_some_and(|v| v.is_object()) {
            saved[&app] = json!({});
        }
        saved[&app][&kind] = json!(on);
        let text = saved.to_string();
        self.as_mut().set_setting(&QString::from("appDevicePermissions"), &QString::from(text.as_str()));
        // Show the change.
        let current: serde_json::Value = serde_json::from_str(&self.rust().app_permissions_json.to_string()).unwrap_or_default();
        if current.get("app").and_then(|a| a.as_str()).is_some_and(|a| a.eq_ignore_ascii_case(&app)) {
            let mut c = current;
            if let Some(items) = c.get_mut("items").and_then(|i| i.as_array_mut()) {
                for it in items.iter_mut().filter(|it| it.get("kind").and_then(|k| k.as_str()) == Some(kind.as_str())) {
                    it["on"] = json!(on);
                }
            }
            self.as_mut().set_app_permissions_json(QString::from(c.to_string().as_str()));
        }
    }

    pub fn store_page_load(mut self: Pin<&mut Self>, id: &QString) {
        let id = id.to_string();
        self.as_mut().set_store_page_json(QString::from(json!({ "id": id, "loading": true }).to_string().as_str()));
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async { api::store_content::store_page(&TeamsClient::new().await?, &id).await }.await;
            let _ = qt.queue(move |mut this| {
                let v = match result {
                    Ok(p) => json!(p),
                    Err(e) => json!({ "id": id, "error": short_error(&e) }),
                };
                this.as_mut().set_store_page_json(QString::from(v.to_string().as_str()));
            });
        });
    }

    pub fn store_search(mut self: Pin<&mut Self>, query: &QString) {
        let q = query.to_string();
        self.as_mut().set_store_search_json(QString::from(json!({ "query": q, "loading": true }).to_string().as_str()));
        if q.trim().is_empty() {
            return;
        }
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async { api::store_content::search_store(&TeamsClient::new().await?, q.trim()).await }.await;
            let _ = qt.queue(move |mut this| {
                let current: serde_json::Value = serde_json::from_str(&this.rust().store_search_json.to_string()).unwrap_or_default();
                if current.get("query").and_then(|x| x.as_str()) != Some(q.as_str()) {
                    return;
                }
                let v = match result {
                    Ok(r) => json!({ "query": q, "results": r }),
                    Err(e) => json!({ "query": q, "results": [], "error": short_error(&e) }),
                };
                this.as_mut().set_store_search_json(QString::from(v.to_string().as_str()));
            });
        });
    }

    pub fn channel_tabs_load(
        mut self: Pin<&mut Self>,
        team_id: &QString,
        channel_id: &QString,
        channel_name: &QString,
    ) {
        let (team, channel, name) = (
            team_id.to_string(),
            channel_id.to_string(),
            channel_name.to_string(),
        );
        self.as_mut().rust_mut().channel_tabs_name = name.clone();
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                api::tabs::channel_tabs(&TeamsClient::new().await?, &team, &channel, &name).await
            }
            .await;
            let _ = qt.queue(move |mut this| {
                let text = match result {
                    Ok(tabs) => json!({ "channel": channel, "tabs": tabs }).to_string(),
                    Err(e) => json!({ "channel": channel, "error": short_error(&e) }).to_string(),
                };
                this.as_mut()
                    .set_channel_tabs_json(QString::from(text.as_str()));
            });
        });
    }

    pub fn sync_call_presence(&self) {
        use teams_cli::api::presence::CallState;
        let state = match (self.call_state.to_string().as_str(), self.call_sharing) {
            ("connected", true) => CallState::Presenting,
            ("connected", false) => CallState::InCall,
            _ => CallState::NotInCall,
        };
        runtime().spawn(async move {
            let http = reqwest::Client::new();
            teams_cli::api::presence::set_call_state(&http, state).await;
        });
    }

    pub fn collect_support_files(&self) {
        // As Teams' tray does: a "<app> Support Logs YYYY MM DD HH MM SS"
        // folder on the Desktop (local time), then the Desktop opened.
        let result = (|| -> anyhow::Result<std::path::PathBuf> {
            let home = std::env::var_os("HOME")
                .map(std::path::PathBuf::from)
                .unwrap_or_default();
            let desktop = xdg_user_dir("DESKTOP").unwrap_or_else(|| home.join("Desktop"));
            let stamp = chrono::Local::now().format("%Y %m %d %H %M %S");
            let dir = desktop.join(format!("OST Support Logs {stamp}"));
            std::fs::create_dir_all(&dir)?;
            std::fs::copy(crate::log_path(), dir.join("ost-desktop.log"))?;
            std::fs::write(
                dir.join("version.txt"),
                format!("OST desktop {}\n", env!("CARGO_PKG_VERSION")),
            )?;
            Ok(desktop)
        })();
        match result {
            Ok(desktop) => {
                let _ = std::process::Command::new("xdg-open").arg(desktop).spawn();
            }
            Err(e) => tracing::warn!("collect support files failed: {e:#}"),
        }
    }

    pub fn app_about_load(self: Pin<&mut Self>, app_id: &QString) {
        let app = app_id.to_string();
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result =
                async { api::tabs::app_about(&TeamsClient::new().await?, &app).await }.await;
            let _ = qt.queue(move |mut this| {
                let text = match result {
                    Ok(about) => json!({ "app": app, "about": about }).to_string(),
                    Err(e) => json!({ "app": app, "error": short_error(&e) }).to_string(),
                };
                this.as_mut()
                    .set_app_about_json(QString::from(text.as_str()));
            });
        });
    }

    pub fn app_details_load(mut self: Pin<&mut Self>, app_id: &QString) {
        let app = app_id.to_string();
        self.as_mut()
            .set_app_details_json(QString::from(json!({ "app": app, "loading": true }).to_string().as_str()));
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                api::app_details::details(&TeamsClient::new().await?, &app).await
            }
            .await;
            let _ = qt.queue(move |mut this| {
                let text = match result {
                    Ok(d) => {
                        let card = api::app_details::share_card(&d);
                        json!({ "app": app, "details": d, "card": card }).to_string()
                    }
                    Err(e) => json!({ "app": app, "error": short_error(&e) }).to_string(),
                };
                this.as_mut().set_app_details_json(QString::from(text.as_str()));
            });
        });
    }

    pub fn app_reviews_load(
        self: Pin<&mut Self>,
        app_id: &QString,
        sort: &QString,
        first: i32,
        append: bool,
    ) {
        let app = app_id.to_string();
        let sort = sort.to_string();
        // The next page continues what's shown, for the same app and order.
        let shown: serde_json::Value =
            serde_json::from_str(&self.rust().app_reviews_json.to_string()).unwrap_or_default();
        let next = (append && shown["app"] == app.as_str() && shown["sort"] == sort.as_str())
            .then(|| shown["next"].as_str().unwrap_or_default().to_string())
            .filter(|n| !n.is_empty());
        if append && next.is_none() {
            return;
        }
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                api::app_details::reviews(
                    &client,
                    &app,
                    api::app_details::ReviewSort::parse(&sort),
                    first.max(1) as usize,
                    next.as_deref(),
                )
                .await
            }
            .await;
            let _ = qt.queue(move |mut this| {
                let text = match result {
                    Ok(page) => {
                        let mut reviews = Vec::new();
                        if append {
                            let shown: serde_json::Value =
                                serde_json::from_str(&this.rust().app_reviews_json.to_string()).unwrap_or_default();
                            if shown["app"] == app.as_str() && shown["sort"] == sort.as_str() {
                                reviews = shown["reviews"].as_array().cloned().unwrap_or_default();
                            }
                        }
                        reviews.extend(page.reviews.iter().map(|r| json!(r)));
                        json!({ "app": app, "sort": sort, "count": page.count, "reviews": reviews,
                                "next": page.next, "more": !page.next.is_empty() })
                        .to_string()
                    }
                    Err(e) => json!({ "app": app, "sort": sort, "error": short_error(&e) }).to_string(),
                };
                this.as_mut().set_app_reviews_json(QString::from(text.as_str()));
            });
        });
    }

    pub fn set_chat_hidden(mut self: Pin<&mut Self>, chat_id: &QString, hidden: bool) {
        let id = chat_id.to_string();
        // Show it at once, as Teams does.
        if let Some(c) = self
            .as_mut()
            .rust_mut()
            .chats
            .iter_mut()
            .find(|c| c["id"].as_str() == Some(id.as_str()))
        {
            c["hidden"] = json!(hidden);
        }
        self.as_mut().publish_chats();
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                api::msgactions::set_chat_hidden(&client, &id, hidden).await
            }
            .await;
            let _ = qt.queue(move |mut this| {
                if let Err(e) = &result {
                    tracing::warn!("hide chat failed: {}", short_error(e));
                }
                this.as_mut().reload_chats();
            });
        });
    }

    pub fn remove_chat_history(mut self: Pin<&mut Self>, chat_id: &QString) {
        let id = chat_id.to_string();
        if let Some(c) = self.as_mut().rust_mut().chats.iter_mut().find(|c| c["id"].as_str() == Some(id.as_str())) {
            c["hidden"] = json!(true);
        }
        self.as_mut().publish_chats();
        // Teams opens the next chat in the list.
        if self.rust().current_chat_id.to_string() == id {
            let next = self
                .rust()
                .chats
                .iter()
                .find(|c| {
                    let cid = c["id"].as_str().unwrap_or_default();
                    cid != id && !cid.starts_with("48:") && !c["hidden"].as_bool().unwrap_or(false) && !c["empty"].as_bool().unwrap_or(false)
                })
                .map(|c| (c["id"].as_str().unwrap_or_default().to_string(), c["name"].as_str().unwrap_or_default().to_string()));
            if let Some((nid, name)) = next {
                self.as_mut().select_chat(&QString::from(nid.as_str()), &QString::from(name.as_str()));
            }
        }
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                api::msgactions::clear_chat_history(&client, &id).await
            }
            .await;
            let _ = qt.queue(move |mut this| {
                if let Err(e) = &result {
                    tracing::warn!("remove chat history failed: {}", short_error(e));
                    this.as_mut().toast("Something went wrong on our end. Please try again.", "error");
                }
                this.as_mut().reload_chats();
            });
        });
    }

    pub fn leave_chat(self: Pin<&mut Self>, chat_id: &QString) {
        let id = chat_id.to_string();
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                let me = client.object_id().context("not signed in")?;
                api::msgactions::leave_chat(&client, &id, &format!("8:orgid:{me}")).await
            }
            .await;
            let _ = qt.queue(move |mut this| match result {
                Ok(()) => {
                    this.as_mut().rust_mut().chats.retain(|c| c["id"].as_str() != Some(id.as_str()));
                    this.as_mut().publish_chats();
                }
                Err(e) => {
                    tracing::warn!("leave chat failed: {}", short_error(&e));
                    this.as_mut().toast("Couldn't leave the chat", "error");
                }
            });
        });
    }

    pub fn chat_member_counts_load(self: Pin<&mut Self>, chat_id: &QString) {
        let id = chat_id.to_string();
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                api::thread_member_ids(&client, &id).await
            }
            .await;
            if let Ok(members) = result {
                let n = members.len();
                let _ = qt.queue(move |mut this| {
                    let mut map: serde_json::Map<String, serde_json::Value> =
                        serde_json::from_str(&this.rust().chat_member_counts_json.to_string()).unwrap_or_default();
                    map.insert(id, json!(n));
                    this.as_mut().set_chat_member_counts_json(QString::from(
                        serde_json::Value::Object(map).to_string().as_str(),
                    ));
                });
            }
        });
    }

    pub fn folders_load(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                api::folders::folders(&TeamsClient::new().await?).await
            }
            .await;
            let _ = qt.queue(move |mut this| match result {
                Ok(f) => {
                    let text = serde_json::to_string(&f).unwrap_or_default();
                    this.as_mut().rust_mut().folders = f;
                    this.as_mut().set_folders_json(QString::from(text.as_str()));
                }
                Err(e) => tracing::warn!("folders: {}", short_error(&e)),
            });
        });
    }

    pub fn folder_action(mut self: Pin<&mut Self>, action: &QString, args: &QString) {
        use api::folders;
        let action = action.to_string();
        let args: serde_json::Value = serde_json::from_str(&args.to_string()).unwrap_or_default();
        let arg = |args: &serde_json::Value, k: &str| args.get(k).and_then(|v| v.as_str()).unwrap_or_default().to_string();
        let current = self.rust().folders.clone();
        let version = current.version;
        // Expanding and collapsing show at once (Teams' optimistic update).
        if action == "expand" || action == "collapse" || action == "expandAll" || action == "collapseAll" {
            let open = action.starts_with("expand");
            let ids: Vec<String> = if action.ends_with("All") {
                current.folders.iter().map(|f| f.id.clone()).collect()
            } else {
                vec![arg(&args, "id")]
            };
            let mut next = current.clone();
            for f in next.folders.iter_mut().filter(|f| ids.contains(&f.id)) {
                f.expanded = open;
            }
            let text = serde_json::to_string(&next).unwrap_or_default();
            self.as_mut().rust_mut().folders = next;
            self.as_mut().set_folders_json(QString::from(text.as_str()));
        }
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let a = |k: &str| arg(&args, k);
            let find = |id: &str| current.folders.iter().find(|f| f.id == id).cloned();
            let result = async {
                let client = TeamsClient::new().await?;
                match action.as_str() {
                    "expand" | "collapse" => {
                        let f = find(&a("id")).context("No such section")?;
                        folders::set_expanded(&client, version, &f, action == "expand").await
                    }
                    "expandAll" | "collapseAll" => {
                        let ids: Vec<String> = current.folders.iter().map(|f| f.id.clone()).collect();
                        folders::set_all_expanded(&client, version, &ids, action == "expandAll").await
                    }
                    "create" => {
                        let item = a("item");
                        let from = a("from");
                        folders::create(
                            &client,
                            version,
                            &a("name"),
                            (!item.is_empty()).then_some(item.as_str()),
                            (!from.is_empty()).then_some(from.as_str()),
                        )
                        .await
                    }
                    "rename" => {
                        let f = find(&a("id")).context("No such section")?;
                        folders::rename(&client, version, &f, &a("name")).await
                    }
                    "delete" => folders::delete(&client, version, &a("id")).await,
                    "move" => {
                        let from = a("from");
                        folders::move_item(&client, version, &a("item"), &a("to"), (!from.is_empty()).then_some(from.as_str())).await
                    }
                    "remove" => folders::remove_item(&client, version, &a("item"), &a("from")).await,
                    _ => anyhow::bail!("Unknown section action"),
                }
            }
            .await;
            let _ = qt.queue(move |mut this| {
                if let Err(e) = &result {
                    tracing::warn!("section action failed: {}", short_error(e));
                }
                // The server's state wins (and the next change needs its version).
                this.as_mut().folders_load();
            });
        });
    }

    pub fn app_links_load(mut self: Pin<&mut Self>, app_id: &QString) {
        let app = app_id.to_string();
        if app.is_empty() || !self.as_mut().rust_mut().app_links_asked.insert(app.clone()) {
            return;
        }
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                api::app_details::definition(&TeamsClient::new().await?, &app).await
            }
            .await;
            let Ok(def) = result else { return };
            let s = |k: &str| def.get(k).and_then(|v| v.as_str()).unwrap_or_default().to_string();
            let entry = json!({
                "privacy": api::tabs::https_url(&s("privacyUrl")),
                "terms": api::tabs::https_url(&s("termsOfUseUrl")),
                "name": s("name"),
            });
            let _ = qt.queue(move |mut this| {
                let mut map: serde_json::Map<String, serde_json::Value> =
                    serde_json::from_str(&this.rust().app_links_json.to_string()).unwrap_or_default();
                map.insert(app, entry);
                this.as_mut().set_app_links_json(QString::from(
                    serde_json::Value::Object(map).to_string().as_str(),
                ));
            });
        });
    }

    pub fn app_similar_load(mut self: Pin<&mut Self>, app_id: &QString) {
        let app = app_id.to_string();
        self.as_mut()
            .set_app_similar_json(QString::from(json!({ "app": app, "apps": [] }).to_string().as_str()));
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                api::app_details::similar(&TeamsClient::new().await?, &app).await
            }
            .await;
            let _ = qt.queue(move |mut this| {
                let apps = result.unwrap_or_else(|e| {
                    tracing::info!("more like this: {}", short_error(&e));
                    Vec::new()
                });
                this.as_mut().set_app_similar_json(QString::from(
                    json!({ "app": app, "apps": apps }).to_string().as_str(),
                ));
            });
        });
    }

    pub fn agent_store_load(mut self: Pin<&mut Self>, conversation_id: &QString, channel: bool) {
        let conv = conversation_id.to_string();
        self.as_mut().set_agent_store_json(QString::from(
            json!({ "conversation": conv, "loading": true }).to_string().as_str(),
        ));
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                let apps = if channel {
                    api::store_content::channel_apps(&client, &conv).await.unwrap_or_default()
                } else {
                    api::store_content::chat_apps(&client, &conv).await.unwrap_or_default()
                };
                api::store_content::in_context(&client, channel, &apps).await
            }
            .await;
            let _ = qt.queue(move |mut this| {
                let v = match result {
                    Ok(ic) => json!({ "conversation": conv, "installed": ic.installed, "collections": ic.collections }),
                    Err(e) => {
                        tracing::warn!("agent store: {}", short_error(&e));
                        json!({ "conversation": conv, "error": short_error(&e) })
                    }
                };
                this.as_mut().set_agent_store_json(QString::from(v.to_string().as_str()));
            });
        });
    }

    pub fn agent_store_search(mut self: Pin<&mut Self>, conversation_id: &QString, channel: bool, query: &QString) {
        let conv = conversation_id.to_string();
        let q = query.to_string();
        self.as_mut().set_agent_search_json(QString::from(json!({ "query": q, "loading": true }).to_string().as_str()));
        if q.trim().is_empty() {
            return;
        }
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                let apps = if channel {
                    api::store_content::channel_apps(&client, &conv).await.unwrap_or_default()
                } else {
                    api::store_content::chat_apps(&client, &conv).await.unwrap_or_default()
                };
                api::store_content::search_agents(&client, q.trim(), channel, &apps).await
            }
            .await;
            let _ = qt.queue(move |mut this| {
                // Only the newest query's answer shows.
                let current: serde_json::Value = serde_json::from_str(&this.rust().agent_search_json.to_string()).unwrap_or_default();
                if current.get("query").and_then(|x| x.as_str()) != Some(q.as_str()) {
                    return;
                }
                let v = match result {
                    Ok(r) => json!({ "query": q, "results": r }),
                    Err(e) => json!({ "query": q, "results": [], "error": short_error(&e) }),
                };
                this.as_mut().set_agent_search_json(QString::from(v.to_string().as_str()));
            });
        });
    }

    pub fn add_app(mut self: Pin<&mut Self>, app_id: &QString, conversation_id: &QString, channel: bool) {
        let app = app_id.to_string();
        let conv = conversation_id.to_string();
        self.as_mut().set_app_added_json(QString::from(
            json!({ "app": app, "conversation": conv, "busy": true }).to_string().as_str(),
        ));
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                let target = (!conv.is_empty()).then_some((conv.as_str(), channel));
                api::store_content::add_app(&client, &app, target).await
            }
            .await;
            let _ = qt.queue(move |mut this| {
                let v = match result {
                    Ok(a) => json!({ "app": app, "conversation": conv, "ok": true, "name": a.name, "bot": a.bot, "notificationOnly": a.notification_only }),
                    Err(e) => {
                        tracing::warn!("add app: {}", short_error(&e));
                        json!({ "app": app, "conversation": conv, "error": short_error(&e) })
                    }
                };
                this.as_mut().set_app_added_json(QString::from(v.to_string().as_str()));
            });
        });
    }

    pub fn share_app(
        mut self: Pin<&mut Self>,
        app_id: &QString,
        targets_json: &QString,
        note: &QString,
        card: bool,
    ) {
        let app = app_id.to_string();
        let note = note.to_string();
        let targets: Vec<serde_json::Value> =
            serde_json::from_str(&targets_json.to_string()).unwrap_or_default();
        let group_chats = group_chat_ids(&self.rust().chats_json.to_string());
        self.as_mut().set_share_state(QString::from("sharing"));
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                let details = api::app_details::details(&client, &app).await?;
                let target = picked_conversation(&client, &targets, &group_chats).await?;
                api::app_details::share(&client, &target, &note, &details, card).await?;
                anyhow::Ok(target)
            }
            .await;
            let _ = qt.queue(move |mut this| match result {
                Ok(target) => {
                    this.as_mut().rust_mut().shared_to = target;
                    this.as_mut().set_share_state(QString::from("shared"));
                }
                Err(e) => {
                    tracing::warn!("share app failed: {}", short_error(&e));
                    this.as_mut().set_share_state(QString::from("error"));
                }
            });
        });
    }

    pub fn report_app_review(
        self: Pin<&mut Self>,
        app_id: &QString,
        review_id: &QString,
        reason: &QString,
        comment: &QString,
    ) {
        let (app, review, reason, comment) =
            (app_id.to_string(), review_id.to_string(), reason.to_string(), comment.to_string());
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                api::app_details::report_review(&client, &app, &review, &reason, &comment).await
            }
            .await;
            let _ = qt.queue(move |mut this| match result {
                Ok(()) => {}
                Err(e) => {
                    tracing::warn!("report review failed: {}", short_error(&e));
                    this.as_mut().toast("Couldn't report the review", "error");
                }
            });
        });
    }

    pub fn shared_conversation(&self) -> QString {
        QString::from(self.shared_to.as_str())
    }

    pub fn post_app_review(
        self: Pin<&mut Self>,
        app_id: &QString,
        rating: i32,
        title: &QString,
        content: &QString,
        anonymous: bool,
    ) {
        let (app, title, content) = (app_id.to_string(), title.to_string(), content.to_string());
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                api::app_details::post_review(&client, &app, rating.clamp(1, 5) as u8, &title, &content, anonymous)
                    .await
            }
            .await;
            let _ = qt.queue(move |mut this| match result {
                Ok(()) => {
                    this.as_mut().toast("Review posted", "success");
                    let id = QString::from(app.as_str());
                    this.as_mut().app_details_load(&id);
                }
                Err(e) => {
                    tracing::warn!("post review failed: {}", short_error(&e));
                    this.as_mut().toast("Couldn't post your review", "error");
                }
            });
        });
    }

    pub fn copy_tab_link(&self, team_id: &QString, channel_id: &QString, tab_json: &QString) {
        let Ok(tab) = serde_json::from_str::<serde_json::Value>(&tab_json.to_string()) else {
            return;
        };
        let s = |k: &str| {
            tab.get(k)
                .and_then(|v| v.as_str())
                .unwrap_or_default()
                .to_string()
        };
        let t = api::tabs::Tab {
            id: s("id"),
            name: s("name"),
            app_id: s("app_id"),
            kind: api::tabs::Kind::Extension,
            entity_id: s("entity_id"),
            content_url: String::new(),
            website_url: String::new(),
            order: 0.0,
            draggable: true,
            opens_in_browser: false,
            menu: Vec::new(),
            context_menu: Vec::new(),
            can_converse: false,
            conversation: String::new(),
            icon: String::new(),
        };
        let tenant = teams_cli::config::Config::load()
            .ok()
            .and_then(|c| c.tenant_id())
            .unwrap_or_default();
        let (link, html) =
            api::tabs::copy_link(&t, &channel_id.to_string(), &team_id.to_string(), &tenant);
        let (Ok(link), Ok(html)) = (std::ffi::CString::new(link), std::ffi::CString::new(html))
        else {
            return;
        };
        // SAFETY: two NUL-terminated strings, copied by Qt before returning.
        unsafe { ost_set_clipboard(link.as_ptr(), html.as_ptr()) };
    }

    pub fn channel_action(
        self: Pin<&mut Self>,
        op: &QString,
        team_id: &QString,
        channel_id: &QString,
        arg: &QString,
    ) {
        let (op, team, channel, arg) = (
            op.to_string(),
            team_id.to_string(),
            channel_id.to_string(),
            arg.to_string(),
        );
        // Your teams and channels' ops are about all your teams.
        if !channel.ends_with("@thread.tacv2") && !matches!(op.as_str(), "quick-saved" | "quick-followed" | "quick-unsave" | "quick-unfollow" | "notify-tagged" | "notify-on" | "notify-off" | "meeting-chat-report-info" | "chat-apps" | "chat-app-remove" | "cross-team-analytics" | "invitations" | "create-team" | "team-templates" | "team-template" | "my-groups" | "teams-suggested" | "teams-find" | "team-join" | "team-join-code") {
            return;
        }
        // The team's thread id and the channel's facts, from the list.
        let teams: serde_json::Value =
            serde_json::from_str(&self.rust().teams_json.to_string()).unwrap_or_default();
        let team_entry = teams
            .as_array()
            .into_iter()
            .flatten()
            .find(|t| t["id"].as_str() == Some(team.as_str()))
            .cloned()
            .unwrap_or_default();
        let team_thread = team_entry["thread_id"].as_str().unwrap_or_default().to_string();
        let general = team_entry["channels"]
            .as_array()
            .into_iter()
            .flatten()
            .any(|c| c["id"].as_str() == Some(channel.as_str()) && c["general"].as_bool() == Some(true));
        if op == "copy-link" || op == "team-link" {
            let tenant = teams_cli::config::Config::load()
                .ok()
                .and_then(|c| c.tenant_id())
                .unwrap_or_default();
            let (url, html) = if op == "team-link" {
                // The team's thread (its General) and Teams' anchor text.
                let general = team_entry["channels"]
                    .as_array()
                    .into_iter()
                    .flatten()
                    .find(|c| c["general"].as_bool() == Some(true))
                    .and_then(|c| c["name"].as_str())
                    .unwrap_or("General")
                    .to_string();
                api::channels::team_link(&team_thread, &general, team_entry["name"].as_str().unwrap_or_default(), &team, &tenant)
            } else {
                api::channels::channel_link(&channel, &arg, &team, &tenant)
            };
            if let (Ok(u), Ok(h)) = (std::ffi::CString::new(url), std::ffi::CString::new(html)) {
                // SAFETY: two NUL-terminated strings, copied by Qt before returning.
                unsafe { ost_set_clipboard(u.as_ptr(), h.as_ptr()) };
                let mut this = self;
                this.as_mut().toast("Copied to clipboard", "success");
            }
            return;
        }
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result: anyhow::Result<serde_json::Value> = async {
                let client = TeamsClient::new().await?;
                use api::channels::{Notify, NotifyMode};
                let mode = |m: &str| match m {
                    "all" => NotifyMode::All,
                    "mute" => NotifyMode::Mute,
                    _ => NotifyMode::Mentions,
                };
                match op.as_str() {
                    "notify-load" => {
                        let props = api::channels::properties(&client, &channel).await?;
                        Ok(serde_json::to_value(api::channels::notify_state_from(&props))?)
                    }
                    "notify" => {
                        let props = api::channels::properties(&client, &channel).await.unwrap_or_default();
                        let dsk = api::channels::notify_state_from(&props).notify.dsk;
                        api::channels::set_notify(&client, &channel, &Notify::for_mode(mode(&arg), dsk)).await?;
                        Ok(serde_json::Value::Null)
                    }
                    "customize" => {
                        let a: serde_json::Value = serde_json::from_str(&arg).unwrap_or_default();
                        let m = mode(a["mode"].as_str().unwrap_or("mentions"));
                        let n = Notify {
                            mode: m,
                            tag: a["tag"].as_bool().unwrap_or(true),
                            channel_team: a["channel_team"].as_bool().unwrap_or(true),
                            dsk: a["dsk"].as_str().map(str::to_string),
                        };
                        api::channels::set_notify(&client, &channel, &n).await?;
                        if let Some(follow) = a["follow_all"].as_bool() {
                            let props = api::channels::properties(&client, &channel).await.unwrap_or_default();
                            if api::channels::notify_state_from(&props).follow_all != follow {
                                let newest = a["newest"].as_str().filter(|s| !s.is_empty());
                                api::channels::set_follow_all(&client, &channel, if follow { newest.or(Some("0")) } else { None }).await?;
                            }
                        }
                        Ok(serde_json::Value::Null)
                    }
                    "hide" | "show" => {
                        api::channels::set_hidden(&client, &channel, general, op == "hide").await?;
                        Ok(serde_json::Value::Null)
                    }
                    "edit" => {
                        let change: api::channels::Edit = serde_json::from_str(&arg).context("Edit")?;
                        api::channels::edit(&client, &team_thread, &channel, &change).await?;
                        Ok(serde_json::Value::Null)
                    }
                    "email" => Ok(serde_json::to_value(api::channels::email(&client, &channel).await?)?),
                    "email-senders" => {
                        let a: serde_json::Value = serde_json::from_str(&arg).unwrap_or_default();
                        let domains: Vec<String> = a["domains"]
                            .as_array()
                            .into_iter()
                            .flatten()
                            .filter_map(|d| d.as_str().map(str::to_string))
                            .collect();
                        let e = api::channels::set_email_senders(&client, &channel, a["allowed"].as_str().unwrap_or("members"), &domains).await?;
                        Ok(serde_json::to_value(e)?)
                    }
                    "email-remove" => {
                        api::channels::remove_email(&client, &channel).await?;
                        Ok(serde_json::Value::Null)
                    }
                    "posts-at-top" | "posts-at-bottom" => {
                        api::channels::set_new_posts_at_bottom(&client, op == "posts-at-bottom").await?;
                        Ok(serde_json::Value::Null)
                    }
                    // Create a channel: arg {name, description, type, layout, recommend}.
                    "create-channel" => {
                        let a: serde_json::Value = serde_json::from_str(&arg).unwrap_or_default();
                        let f = |k: &str| a[k].as_str().unwrap_or_default().to_string();
                        let id = api::channels::create_channel(
                            &client,
                            &team_thread,
                            &team,
                            &f("name"),
                            &f("description"),
                            if f("type").is_empty() { "Standard" } else { a["type"].as_str().unwrap_or("Standard") },
                            if f("layout") == "PostReply" { "PostReply" } else { "Conversational" },
                            a["recommend"].as_bool().unwrap_or(false),
                        )
                        .await?;
                        Ok(json!({ "id": id, "name": f("name").trim(), "type": a["type"] }))
                    }
                    // A channel's Archive / Restore / Delete / Recommend.
                    "archive" | "restore" => {
                        let a: serde_json::Value = serde_json::from_str(&arg).unwrap_or_default();
                        api::channels::archive_channel(&client, &team, &channel, op == "restore", a["readOnly"].as_bool().unwrap_or(false)).await?;
                        Ok(serde_json::Value::Null)
                    }
                    "delete-channel" => {
                        api::channels::delete_channel(&client, &team_thread, &team, &channel).await?;
                        Ok(serde_json::Value::Null)
                    }
                    "recommend" | "unrecommend" => {
                        api::channels::recommend_channel(&client, &channel, op == "recommend").await?;
                        Ok(serde_json::Value::Null)
                    }
                    // The team row's Hide all channels.
                    "hide-all" => {
                        api::channels::hide_all_channels(&client, &team_thread).await?;
                        Ok(serde_json::Value::Null)
                    }
                    // Manage channel ▸ Settings ▸ Moderation (General).
                    "moderation-load" => {
                        let s = api::channels::space_admin_settings(&client, &team_thread).await?;
                        Ok(json!({ "general": api::channels::general_channel_setting(&s) }))
                    }
                    "moderation" => {
                        let value: u8 = arg.parse().context("Moderation")?;
                        api::channels::set_general_channel_setting(&client, &team_thread, value).await?;
                        Ok(json!({ "general": value }))
                    }
                    // Moderation for other channels: the settings, the team's
                    // owners and the added moderators.
                    "channel-settings-load" => {
                        let s = api::channels::channel_settings(&client, &channel).await?;
                        let owners = api::channels::team_owners(&client, &team_thread).await.unwrap_or_default();
                        let moderators = if s.moderated() {
                            api::channels::channel_moderators(&client, &channel).await.unwrap_or_default()
                        } else {
                            Vec::new()
                        };
                        Ok(json!({ "settings": s, "owners": owners, "moderators": moderators }))
                    }
                    // arg {post?, replies?, pins?, bots?, connectors?, reset}:
                    // the change on the channel's current settings, or on
                    // Teams' defaults when `reset` (turning moderation On or
                    // Off), written back whole.
                    "channel-settings" => {
                        let a: serde_json::Value = serde_json::from_str(&arg).context("Settings")?;
                        let mut s = if a["reset"].as_bool() == Some(true) {
                            api::channels::ChannelSettings::default()
                        } else {
                            api::channels::channel_settings(&client, &channel).await?
                        };
                        if let Some(p) = a["post"].as_u64() {
                            s.post = p.min(2) as u8;
                        }
                        for (key, field) in [("replies", &mut s.replies), ("pins", &mut s.pins), ("bots", &mut s.bots), ("connectors", &mut s.connectors)] {
                            if let Some(b) = a[key].as_bool() {
                                *field = b;
                            }
                        }
                        api::channels::set_channel_settings(&client, &channel, &s).await?;
                        let moderators = if s.moderated() {
                            api::channels::channel_moderators(&client, &channel).await.unwrap_or_default()
                        } else {
                            Vec::new()
                        };
                        Ok(json!({ "settings": s, "moderators": moderators }))
                    }
                    // The team menu's Archive (arg {readOnly}) / Restore team,
                    // Leave and Delete.
                    "team-archive" | "team-restore" => {
                        let a: serde_json::Value = serde_json::from_str(&arg).unwrap_or_default();
                        api::channels::archive_team(&client, &team, op == "team-restore", a["readOnly"].as_bool().unwrap_or(false)).await?;
                        Ok(serde_json::Value::Null)
                    }
                    "team-leave" => {
                        let code = api::channels::leave_team(&client, &team_thread, &team).await?;
                        Ok(json!({ "code": code }))
                    }
                    // Manage team ▸ Members.
                    "team-roster" => {
                        let r = api::channels::team_roster(&client, &team_thread).await?;
                        Ok(json!({ "members": r }))
                    }
                    // arg {mri, update: Promoted | Demoted | Left}.
                    "team-membership" => {
                        let a: serde_json::Value = serde_json::from_str(&arg).context("Member")?;
                        let update = a["update"].as_str().unwrap_or_default();
                        anyhow::ensure!(matches!(update, "Promoted" | "Demoted" | "Left"), "Unknown change");
                        let code = api::channels::update_membership(&client, &team_thread, &team, a["mri"].as_str().unwrap_or_default(), update).await?;
                        Ok(json!({ "code": code, "mri": a["mri"], "update": update }))
                    }
                    // Manage team ▸ Settings: the team's admin settings, its
                    // tag settings and its code.
                    "team-settings-load" => {
                        let s = api::channels::space_admin_settings(&client, &team_thread).await?;
                        let settings: serde_json::Value = serde_json::from_str(&s).unwrap_or_default();
                        let tags = api::teams::tag_settings(&client, &team_thread).await.ok();
                        let code = api::channels::team_join_code(&client, &team_thread, reqwest::Method::GET).await.ok().flatten();
                        Ok(json!({ "settings": settings, "tags": tags, "code": code }))
                    }
                    // arg {userSettings: {…}, guestSettings: {…}}.
                    "team-settings" => {
                        let changes: serde_json::Value = serde_json::from_str(&arg).context("Settings")?;
                        let s = api::channels::set_team_settings(&client, &team_thread, &changes).await?;
                        let settings: serde_json::Value = serde_json::from_str(&s).unwrap_or_default();
                        Ok(json!({ "settings": settings }))
                    }
                    // arg {onlyOwners?, shifts?}.
                    "team-tag-settings" => {
                        let a: serde_json::Value = serde_json::from_str(&arg).context("Tags")?;
                        let mut t = api::teams::tag_settings(&client, &team_thread).await?;
                        if let Some(o) = a["onlyOwners"].as_bool() {
                            t.only_owners = o;
                        }
                        if let Some(on) = a["shifts"].as_bool() {
                            t.disallowed_sources.retain(|x| x != "Shifts");
                            if !on {
                                t.disallowed_sources.push("Shifts".into());
                            }
                        }
                        api::teams::set_tag_settings(&client, &team_thread, &t).await?;
                        let t = api::teams::tag_settings(&client, &team_thread).await?;
                        Ok(json!({ "tags": t }))
                    }
                    // arg {name?, description?, public?}.
                    "team-edit" => {
                        let a: serde_json::Value = serde_json::from_str(&arg).context("Team")?;
                        api::channels::edit_team(&client, &team_thread, a["name"].as_str(), a["description"].as_str(), a["public"].as_bool()).await?;
                        Ok(serde_json::Value::Null)
                    }
                    // arg {path}: a picture file, or none for Teams' default
                    // (Remove).
                    "team-picture" => {
                        let a: serde_json::Value = serde_json::from_str(&arg).unwrap_or_default();
                        let image = match a["path"].as_str().filter(|p| !p.is_empty()) {
                            Some(p) => std::fs::read(p.strip_prefix("file://").unwrap_or(p)).context("Picture")?,
                            None => {
                                let name = team_entry["name"].as_str().unwrap_or_default().to_string();
                                api::channels::team_default_picture(&client, &name).await?
                            }
                        };
                        api::channels::set_team_picture(&client, &team, &team_thread, image).await?;
                        Ok(serde_json::Value::Null)
                    }
                    // arg generate | remove.
                    "team-code" => {
                        let method = if arg == "remove" { reqwest::Method::DELETE } else { reqwest::Method::PUT };
                        let mut code = api::channels::team_join_code(&client, &team_thread, method).await?;
                        if arg != "remove" && code.is_none() {
                            code = api::channels::team_join_code(&client, &team_thread, reqwest::Method::GET).await?;
                        }
                        Ok(json!({ "code": if arg == "remove" { None } else { code } }))
                    }
                    // A private channel's member step: arg {channel, users: [{mri, owner}]}.
                    "channel-add-members" => {
                        let a: serde_json::Value = serde_json::from_str(&arg).context("Members")?;
                        let users: Vec<(String, bool)> = a["users"]
                            .as_array()
                            .into_iter()
                            .flatten()
                            .filter_map(|u| Some((u["mri"].as_str()?.to_string(), u["owner"].as_bool().unwrap_or(false))))
                            .collect();
                        let ch = a["channel"].as_str().unwrap_or_default().to_string();
                        api::channels::add_private_channel_members(&client, &team_thread, &ch, &users).await?;
                        Ok(json!({ "added": users.len() }))
                    }
                    // Manage team ▸ Apps.
                    "team-apps" => {
                        let mut apps = api::store_content::team_apps(&client, &team_thread).await?;
                        // The app CDN sends icons as application/octet-stream,
                        // which Qt's network image loader won't decode: keep
                        // them in the private image cache and show the files.
                        for a in apps.iter_mut().filter(|a| a.icon.starts_with("https://")) {
                            if let Ok(path) = public_image_file(&client, &a.icon).await {
                                a.icon = format!("file://{}", path.display());
                            }
                        }
                        Ok(json!({ "apps": apps }))
                    }
                    // Notify when available (Teams' contacts v3 "Tagged"):
                    // who is tagged, tag {mri}, untag {id, mri, email}.
                    "notify-tagged" => {
                        let t = api::contacts::tagged(&client).await?;
                        Ok(json!(t.iter().map(|(mri, id, email)| json!({ "mri": mri, "id": id, "email": email })).collect::<Vec<_>>()))
                    }
                    "notify-on" => {
                        let a: serde_json::Value = serde_json::from_str(&arg).unwrap_or_default();
                        let mri = a["mri"].as_str().unwrap_or_default();
                        let id = api::contacts::notify_when_available(&client, mri).await?;
                        Ok(json!({ "mri": mri.to_lowercase(), "id": id }))
                    }
                    "notify-off" => {
                        let a: serde_json::Value = serde_json::from_str(&arg).unwrap_or_default();
                        let f = |k: &str| a[k].as_str().unwrap_or_default().to_string();
                        api::contacts::stop_notify(&client, &f("id"), &f("mri"), &f("email")).await?;
                        Ok(json!({ "mri": f("mri").to_lowercase() }))
                    }
                    // Remove chat history (Teams' chat menu; it affects you
                    // only): `DELETE {chatsvc}/v1/threads/{chat}`.
                    // A meeting chat's Report a concern: its meeting
                    // {title, start, organizer, ical} and who can be
                    // reported (its members but you).
                    "meeting-chat-report-info" => {
                        let m = api::chat_meeting(&client, &channel).await?.unwrap_or_default();
                        let members = api::chat_members(&client, &channel).await.unwrap_or_default();
                        let org_mri = format!("8:orgid:{}", m.organizer_id).to_ascii_lowercase();
                        let mut organizer = members
                            .iter()
                            .find(|p| p.mri.to_ascii_lowercase() == org_mri)
                            .map(|p| p.name.clone())
                            .unwrap_or_default();
                        if organizer.is_empty()
                            && m.organizer_id.len() == 36 && m.organizer_id.chars().all(|c| c.is_ascii_hexdigit() || c == '-')
                            && let Ok(resp) = client.graph_get(&format!("/users/{}?$select=displayName", m.organizer_id)).await
                            && let Ok(v) = resp.json::<serde_json::Value>().await
                        {
                            organizer = v["displayName"].as_str().unwrap_or_default().to_string();
                        }
                        let people: Vec<_> = members
                            .iter()
                            .filter(|p| !p.me && !p.mri.starts_with("28:"))
                            .map(|p| serde_json::json!({ "id": p.mri, "name": p.name }))
                            .collect();
                        Ok(serde_json::json!({ "title": m.subject, "start": m.start, "organizer": organizer, "ical": m.ical_uid, "people": people }))
                    }
                    // Quick views ▸ Saved and Followed threads (Teams'
                    // 48:saved / 48:threads); unsave {thread, chain, message};
                    // unfollow {thread, chain}.
                    "quick-saved" => Ok(serde_json::to_value(api::quick_views::saved(&client).await?)?),
                    "quick-followed" => Ok(serde_json::to_value(api::quick_views::followed(&client).await?)?),
                    "quick-unsave" => {
                        let a: serde_json::Value = serde_json::from_str(&arg).unwrap_or_default();
                        let f = |k: &str| a[k].as_str().unwrap_or_default().to_string();
                        api::msgactions::set_saved(&client, &f("thread"), &f("chain"), &f("message"), false).await?;
                        Ok(serde_json::Value::Null)
                    }
                    "quick-unfollow" => {
                        let a: serde_json::Value = serde_json::from_str(&arg).unwrap_or_default();
                        let f = |k: &str| a[k].as_str().unwrap_or_default().to_string();
                        api::msgactions::set_following(&client, &f("thread"), &f("chain"), false).await?;
                        Ok(serde_json::Value::Null)
                    }
                    // A chat's Manage apps: its installed apps with names,
                    // publishers and pictures from their definitions.
                    "chat-apps" => {
                        let ents = api::store_content::chat_apps(&client, &channel).await?;
                        // Teams lists the apps added to the chat (Installed),
                        // not the built-in permanent ones.
                        let installed = ["Installed"];
                        let ids: Vec<String> = ents.iter().filter(|(_, st)| installed.contains(&st.as_str())).map(|(id, _)| id.clone()).collect();
                        let defs = api::team_create::definitions(&client, &ids).await.unwrap_or_default();
                        let mut apps = Vec::new();
                        for (id, state) in ents.iter().filter(|(_, st)| installed.contains(&st.as_str())) {
                            let Some(d) = defs.iter().find(|d| d["id"].as_str().is_some_and(|x| x.eq_ignore_ascii_case(id))) else { continue };
                            let mut icon = [d["largeImageUrl"].as_str(), d["smallImageUrl"].as_str()].into_iter().flatten().find(|u| !u.is_empty()).unwrap_or_default().to_string();
                            if icon.starts_with("https://")
                                && let Ok(path) = public_image_file(&client, &icon).await
                            {
                                icon = format!("file://{}", path.display());
                            }
                            apps.push(json!({ "id": id, "name": d["name"], "publisher": d["developerName"], "icon": icon, "state": state }));
                        }
                        apps.sort_by_key(|a| a["name"].as_str().unwrap_or_default().to_lowercase());
                        Ok(json!({ "apps": apps }))
                    }
                    "chat-app-remove" => {
                        api::store_content::remove_from_chat(&client, &channel, arg.trim()).await?;
                        Ok(json!({ "id": arg }))
                    }
                    "team-app-remove" => {
                        api::store_content::remove_from_team(&client, &team_thread, arg.trim()).await?;
                        Ok(json!({ "id": arg }))
                    }
                    // arg {name, description, url, icon}: icon a PNG file path.
                    "team-webhook" => {
                        let a: serde_json::Value = serde_json::from_str(&arg).context("Webhook")?;
                        let icon = a["icon"].as_str().filter(|p| !p.is_empty()).map(|p| p.strip_prefix("file://").unwrap_or(p).to_string());
                        api::store_content::create_outgoing_webhook(&client, &team_thread, a["name"].as_str().unwrap_or_default(), a["description"].as_str().unwrap_or_default(), a["url"].as_str().unwrap_or_default(), icon.as_deref()).await?;
                        Ok(serde_json::Value::Null)
                    }
                    // Manage team ▸ Pending requests.
                    "join-requests" => {
                        let r = api::channels::join_requests(&client, &team).await?;
                        Ok(json!({ "requests": r }))
                    }
                    // arg {mris, accept}.
                    "join-answer" => {
                        let a: serde_json::Value = serde_json::from_str(&arg).context("Requests")?;
                        let mris: Vec<String> = a["mris"].as_array().into_iter().flatten().filter_map(|m| m.as_str().map(str::to_string)).collect();
                        let accept = a["accept"].as_bool().unwrap_or(false);
                        api::channels::answer_join_requests(&client, &team, &mris, accept).await?;
                        Ok(json!({ "mris": mris, "accept": accept }))
                    }
                    "team-delete" => {
                        api::channels::delete_team(&client, &team_thread).await?;
                        Ok(serde_json::Value::Null)
                    }
                    // Manage team ▸ Tags.
                    "tags-load" => {
                        let list = api::teams::tag_list(&client, &team_thread).await?;
                        Ok(json!(list))
                    }
                    // arg: the tag id → its people.
                    "tag-members" => {
                        let mris = api::teams::tag_members(&client, &team_thread, arg.trim()).await?;
                        let people = api::teams::tag_people(&client, &mris).await;
                        Ok(json!({ "tag": arg, "people": people }))
                    }
                    "tag-member-search" => {
                        let people = api::channels::search_team_members(&client, &team_thread, arg.trim()).await?;
                        Ok(json!({ "query": arg, "people": people }))
                    }
                    // arg {name, description, members}.
                    "tag-create" => {
                        let a: serde_json::Value = serde_json::from_str(&arg).context("Tag")?;
                        let members: Vec<String> = a["members"].as_array().into_iter().flatten().filter_map(|m| m.as_str().map(str::to_string)).collect();
                        api::teams::create_tag(&client, &team_thread, a["name"].as_str().unwrap_or_default(), a["description"].as_str().unwrap_or_default(), &members).await?;
                        Ok(json!({ "name": a["name"] }))
                    }
                    // arg {id, version, name, description}.
                    "tag-update" => {
                        let a: serde_json::Value = serde_json::from_str(&arg).context("Tag")?;
                        api::teams::update_tag(&client, &team_thread, a["id"].as_str().unwrap_or_default(), a["version"].as_u64().unwrap_or(0), a["name"].as_str().unwrap_or_default(), a["description"].as_str().unwrap_or_default()).await?;
                        Ok(json!({ "id": a["id"] }))
                    }
                    "tag-delete" | "tag-restore" => {
                        api::teams::delete_tag(&client, &team_thread, arg.trim(), op == "tag-restore").await?;
                        Ok(json!({ "id": arg }))
                    }
                    // arg {id, name, members}.
                    "tag-add-members" | "tag-remove-members" => {
                        let a: serde_json::Value = serde_json::from_str(&arg).context("Tag")?;
                        let members: Vec<String> = a["members"].as_array().into_iter().flatten().filter_map(|m| m.as_str().map(str::to_string)).collect();
                        api::teams::change_tag_members(&client, &team_thread, a["id"].as_str().unwrap_or_default(), a["name"].as_str().unwrap_or_default(), &members, op == "tag-add-members").await?;
                        Ok(json!({ "id": a["id"] }))
                    }
                    // Add members to {team}: who is in it already.
                    "team-members-load" => {
                        let mris = api::channels::team_member_mris(&client, &team_thread).await?;
                        Ok(json!({ "members": mris }))
                    }
                    // Its search (people, groups, lists).
                    "add-member-search" => {
                        let found = api::channels::search_add_candidates(&client, arg.trim()).await?;
                        Ok(json!({ "query": arg, "people": found }))
                    }
                    // A picked group's people (arg: its object id).
                    "group-people" => {
                        let people = api::channels::group_people(&client, arg.trim()).await?;
                        Ok(json!({ "group": arg, "people": people }))
                    }
                    // arg {users: [{mri, owner}], guests: [{email, name}]}.
                    "add-members" => {
                        let a: serde_json::Value = serde_json::from_str(&arg).context("Members")?;
                        let group_id = team.clone();
                        let users: Vec<(String, bool)> = a["users"]
                            .as_array()
                            .into_iter()
                            .flatten()
                            .filter_map(|u| Some((u["mri"].as_str()?.to_string(), u["owner"].as_bool().unwrap_or(false))))
                            .collect();
                        let requested = users.len() + a["guests"].as_array().map(|g| g.len()).unwrap_or(0);
                        let mut outcome = match api::channels::add_team_members(&client, &team_thread, &group_id, &users).await {
                            Ok(o) => o,
                            Err(e) => {
                                tracing::warn!("add members failed: {e:#}");
                                api::channels::AddOutcome { added: 0, failed: users.len() }
                            }
                        };
                        for g in a["guests"].as_array().into_iter().flatten() {
                            let email = g["email"].as_str().unwrap_or_default();
                            match api::channels::invite_guest(&client, &team_thread, &group_id, email, g["name"].as_str().unwrap_or_default()).await {
                                Ok(()) => outcome.added += 1,
                                Err(e) => {
                                    tracing::warn!("guest invite failed: {e:#}");
                                    outcome.failed += 1;
                                }
                            }
                        }
                        Ok(json!({ "requested": requested, "added": outcome.added, "failed": outcome.failed }))
                    }
                    // Add or remove moderators: search the team's members.
                    "moderator-search" => {
                        let people = api::channels::search_team_members(&client, &team_thread, arg.trim()).await?;
                        Ok(json!({ "query": arg, "people": people }))
                    }
                    // arg {add: [mri], remove: [mri]}.
                    "moderators" => {
                        let a: serde_json::Value = serde_json::from_str(&arg).context("Moderators")?;
                        let list = |k: &str| -> Vec<String> {
                            a[k].as_array().into_iter().flatten().filter_map(|v| v.as_str().map(str::to_string)).collect()
                        };
                        let (add, remove) = (list("add"), list("remove"));
                        let changed = api::channels::set_moderators(&client, &channel, &add, &remove).await;
                        let moderators = api::channels::channel_moderators(&client, &channel).await.unwrap_or_default();
                        match changed {
                            Ok(()) => Ok(json!({ "moderators": moderators })),
                            // Teams' toast for what failed.
                            Err(e) => {
                                tracing::warn!("moderators failed: {e:#}");
                                let msg = match (add.is_empty(), remove.is_empty()) {
                                    (false, false) => "There was an error adding or removing moderators.",
                                    (true, false) => "There was an error removing moderators.",
                                    _ => "There was an error adding moderators.",
                                };
                                Ok(json!({ "moderators": moderators, "error": msg }))
                            }
                        }
                    }
                    // Manage channel ▸ Analytics: arg {"period", "team": bool}.
                    "analytics" => {
                        let a: serde_json::Value = serde_json::from_str(&arg).unwrap_or_default();
                        let period = a["period"].as_str().unwrap_or("last-seven-days");
                        let scope = if a["team"].as_bool() == Some(true) { None } else { Some(channel.as_str()) };
                        let r = api::channels::analytics(&client, &team, scope, period).await?;
                        Ok(json!({ "period": api::channels::analytics_period(period), "team": scope.is_none(), "analytics": r }))
                    }
                    // Your teams and channels ▸ Analytics: arg {period, cursor}.
                    "cross-team-analytics" => {
                        let a: serde_json::Value = serde_json::from_str(&arg).unwrap_or_default();
                        let period = a["period"].as_str().unwrap_or("last-seven-days");
                        let cursor = a["cursor"].as_str().unwrap_or_default();
                        let r = api::channels::cross_team_analytics(&client, period, cursor).await?;
                        Ok(json!({ "period": api::channels::analytics_period(period), "cursor": cursor, "analytics": r }))
                    }
                    // Your teams and channels ▸ Pending invites.
                    "invitations" => Ok(serde_json::to_value(api::channels::invitations(&client).await?)?),
                    // Create team: arg {mode: scratch | template | clone |
                    // group, name, description, public, firstChannel,
                    // template: {id, locale, channels, appIds}, groupId,
                    // pick: {tabs, settings, members}, group: {…}}.
                    "create-team" => {
                        let a: serde_json::Value = serde_json::from_str(&arg).context("Create team")?;
                        let f = |k: &str| a[k].as_str().unwrap_or_default().to_string();
                        let public = a["public"].as_bool().unwrap_or(false);
                        let created = match a["mode"].as_str().unwrap_or("scratch") {
                            "template" => {
                                let t = &a["template"];
                                let channels: Vec<serde_json::Value> = t["channels"].as_array().cloned().unwrap_or_default();
                                let apps: Vec<String> = t["appIds"].as_array().into_iter().flatten().filter_map(|x| x.as_str().map(str::to_string)).collect();
                                let body = api::team_create::template_body(
                                    t["id"].as_str().unwrap_or_default(),
                                    t["locale"].as_str().unwrap_or("en-US"),
                                    &f("name"),
                                    &f("description"),
                                    public,
                                    &channels,
                                    &apps,
                                );
                                api::team_create::create_from_template(&client, &body).await?
                            }
                            "clone" => {
                                let pick = api::team_create::ClonePick {
                                    tabs: a["pick"]["tabs"].as_bool().unwrap_or(true),
                                    settings: a["pick"]["settings"].as_bool().unwrap_or(true),
                                    members: a["pick"]["members"].as_bool().unwrap_or(false),
                                };
                                let owner = client.object_id().unwrap_or_default();
                                let body = api::team_create::clone_body(&f("groupId"), &owner, &f("name"), &f("description"), public, pick);
                                api::team_create::clone_team(&client, &f("groupId"), &body).await?
                            }
                            "group" => {
                                let g = &a["group"];
                                let group = api::team_create::Group {
                                    id: g["id"].as_str().unwrap_or_default().to_string(),
                                    name: g["name"].as_str().unwrap_or_default().to_string(),
                                    description: g["description"].as_str().unwrap_or_default().to_string(),
                                    mail: g["mail"].as_str().unwrap_or_default().to_string(),
                                    members: g["members"].as_u64().unwrap_or(0),
                                };
                                api::team_create::create_from_group(&client, &group).await?
                            }
                            _ => {
                                let body = api::team_create::scratch_body(&f("name"), &f("description"), public, &f("firstChannel"));
                                api::team_create::create_from_scratch(&client, &body).await?
                            }
                        };
                        Ok(serde_json::to_value(created)?)
                    }
                    // Template and app pictures go through the private image
                    // cache (the CDN's content types don't suit Qt's loader).
                    "team-templates" => {
                        let mut list = api::team_create::templates(&client, "en-us").await?;
                        for t in list.iter_mut().filter(|t| t.icon.starts_with("https://")) {
                            if let Ok(path) = public_image_file(&client, &t.icon).await {
                                t.icon = format!("file://{}", path.display());
                            }
                        }
                        Ok(serde_json::to_value(list)?)
                    }
                    "team-template" => {
                        let a: serde_json::Value = serde_json::from_str(&arg).unwrap_or_default();
                        let mut d = api::team_create::template_details(&client, a["path"].as_str().unwrap_or_default(), "en-US").await?;
                        for app in d.apps.iter_mut() {
                            if let Some(url) = app["icon"].as_str().filter(|u| u.starts_with("https://")).map(str::to_string)
                                && let Ok(path) = public_image_file(&client, &url).await
                            {
                                app["icon"] = json!(format!("file://{}", path.display()));
                            }
                        }
                        Ok(serde_json::to_value(d)?)
                    }
                    "my-groups" => Ok(serde_json::to_value(api::team_create::my_groups(&client).await?)?),
                    // Join a team: suggestions, search {q, skip}, join
                    // {groupId}, join with a code {code}.
                    "teams-suggested" => Ok(serde_json::to_value(api::team_create::suggested(&client).await?)?),
                    "teams-find" => {
                        let a: serde_json::Value = serde_json::from_str(&arg).unwrap_or_default();
                        let q = a["q"].as_str().unwrap_or_default();
                        let (teams, skip) = api::team_create::find(&client, q, a["skip"].as_str().unwrap_or_default()).await?;
                        Ok(json!({ "q": q, "teams": teams, "skip": skip }))
                    }
                    "team-join" => {
                        let a: serde_json::Value = serde_json::from_str(&arg).unwrap_or_default();
                        let g = a["groupId"].as_str().unwrap_or_default();
                        let r = api::team_create::join(&client, g).await?;
                        Ok(json!({ "groupId": g, "reply": r }))
                    }
                    "team-join-code" => {
                        let a: serde_json::Value = serde_json::from_str(&arg).unwrap_or_default();
                        Ok(api::team_create::join_by_code(&client, a["code"].as_str().unwrap_or_default()).await?)
                    }
                    _ => anyhow::bail!("Unknown channel action"),
                }
            }
            .await;
            let _ = qt.queue(move |mut this| {
                if let Err(e) = &result {
                    tracing::warn!("channel {op} failed: {e:#}");
                }
                let outcome = match &result {
                    Ok(data) => json!({ "op": op, "channel": channel, "ok": true, "data": data }),
                    Err(e) => json!({ "op": op, "channel": channel, "ok": false, "error": short_error(e) }),
                };
                this.as_mut()
                    .set_channel_action_result(QString::from(outcome.to_string().as_str()));
                if result.is_ok() && op == "team-picture" {
                    this.as_mut().forget_photos(&format!("team:{team}"));
                }
                if result.is_ok() && (op == "posts-at-top" || op == "posts-at-bottom") {
                    this.as_mut().set_channel_posts_at_top(op == "posts-at-top");
                }
                if !matches!(op.as_str(), "notify-load" | "email" | "email-senders" | "email-remove" | "posts-at-top" | "posts-at-bottom" | "moderation-load" | "moderation" | "channel-settings-load" | "channel-settings" | "moderator-search" | "moderators" | "team-members-load" | "add-member-search" | "group-people" | "add-members" | "tags-load" | "tag-members" | "tag-member-search" | "tag-create" | "tag-update" | "tag-delete" | "tag-restore" | "tag-add-members" | "tag-remove-members" | "team-roster" | "team-membership" | "join-requests" | "join-answer" | "team-settings-load" | "team-settings" | "team-tag-settings" | "team-code" | "team-apps" | "team-app-remove" | "team-webhook" | "channel-add-members" | "analytics" | "cross-team-analytics" | "invitations" | "chat-apps" | "chat-app-remove" | "meeting-chat-report-info" | "notify-tagged" | "notify-on" | "notify-off" | "quick-saved" | "quick-followed" | "quick-unsave" | "quick-unfollow" | "team-templates" | "team-template" | "my-groups" | "teams-suggested" | "teams-find") {
                    this.as_mut().load_teams();
                }
            });
        });
    }

    pub fn channel_tab_change(
        self: Pin<&mut Self>,
        op: &QString,
        team_id: &QString,
        channel_id: &QString,
        tab_id: &QString,
        arg: &QString,
    ) {
        let (op, team, channel, tab, arg) = (
            op.to_string(),
            team_id.to_string(),
            channel_id.to_string(),
            tab_id.to_string(),
            arg.to_string(),
        );
        let qt = self.qt_thread();
        let tabs_name = self.rust().channel_tabs_name.clone();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                match op.as_str() {
                    "rename" => api::tabs::rename(&client, &channel, &tab, &arg).await.map(|_| String::new()),
                    "remove" => api::tabs::remove(&client, &channel, &tab).await.map(|_| String::new()),
                    "left" | "right" => {
                        api::tabs::move_tab(&client, &channel, &tab, op == "right").await.map(|_| String::new())
                    }
                    // A drag and drop: arg is the place among the movable tabs.
                    "to" => {
                        let to: usize = arg.parse().context("No such place")?;
                        api::tabs::move_tab_to(&client, &channel, &tab, to).await.map(|_| String::new())
                    }
                    "converse" => {
                        let tabs = api::tabs::channel_tabs(&client, &team, &channel, &tabs_name).await?;
                        let t = tabs.iter().find(|t| t.id == tab).context("The tab is gone")?;
                        api::tabs::start_conversation(&client, &channel, t).await
                    }
                    _ => Err(anyhow::anyhow!("Unknown tab change")),
                }
            }
            .await;
            let _ = qt.queue(move |mut this| {
                if let Err(e) = &result {
                    tracing::warn!("tab {op} failed: {e:#}");
                }
                let root = result.as_ref().map(|r| r.clone()).unwrap_or_default();
                let outcome = json!({ "op": op, "tab": tab, "ok": result.is_ok(), "root": root }).to_string();
                this.as_mut()
                    .set_channel_tab_result(QString::from(outcome.as_str()));
                let name = QString::from(this.rust().channel_tabs_name.as_str());
                this.as_mut().channel_tabs_load(
                    &QString::from(team.as_str()),
                    &QString::from(channel.as_str()),
                    &name,
                );
            });
        });
    }

    pub fn channel_files_load(
        mut self: Pin<&mut Self>,
        team_id: &QString,
        channel_id: &QString,
        drive_id: &QString,
        item_id: &QString,
    ) {
        let (team, channel, drive, item) = (
            team_id.to_string(),
            channel_id.to_string(),
            drive_id.to_string(),
            item_id.to_string(),
        );
        self.as_mut().set_channel_files_busy(true);
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let c = TeamsClient::new().await?;
                let (folder, root) = if drive.is_empty() || item.is_empty() {
                    let f = api::drive::channel_folder(&c, &team, &channel).await?;
                    (f.clone(), Some(f))
                } else {
                    (api::drive::DriveItem { drive_id: drive.clone(), id: item.clone(), ..Default::default() }, None)
                };
                let items = api::drive::children(&c, &folder.drive_id, &folder.id).await?;
                let mut out = json!({ "channel": channel, "drive_id": folder.drive_id, "item_id": folder.id, "items": items });
                if let Some(r) = root {
                    out["root"] = json!(r);
                }
                anyhow::Ok(out)
            }
            .await;
            let _ = qt.queue(move |mut this| {
                this.as_mut().set_channel_files_busy(false);
                let text = match result {
                    Ok(v) => v.to_string(),
                    Err(e) => json!({ "error": short_error(&e) }).to_string(),
                };
                this.as_mut().set_channel_files_json(QString::from(text.as_str()));
            });
        });
    }

    pub fn channel_files_change(
        mut self: Pin<&mut Self>,
        op: &QString,
        drive_id: &QString,
        item_id: &QString,
        arg: &QString,
    ) {
        let (op, drive, item, arg) = (
            op.to_string(),
            drive_id.to_string(),
            item_id.to_string(),
            arg.to_string(),
        );
        self.as_mut().set_channel_files_busy(true);
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let c = TeamsClient::new().await?;
                match op.as_str() {
                    "upload" => {
                        for p in arg.lines().map(str::trim).filter(|p| !p.is_empty()) {
                            api::drive::upload(&c, &drive, &item, std::path::Path::new(p)).await?;
                        }
                    }
                    "folder" => {
                        api::drive::new_folder(&c, &drive, &item, &arg).await?;
                    }
                    "delete" => api::drive::delete(&c, &drive, &arg).await?,
                    "shortcut" => api::drive::add_shortcut(&c, &drive, &item, &arg).await?,
                    _ => anyhow::bail!("Unknown change"),
                }
                let items = api::drive::children(&c, &drive, &item).await?;
                anyhow::Ok((
                    op,
                    json!({ "drive_id": drive, "item_id": item, "items": items }),
                ))
            }
            .await;
            let _ = qt.queue(move |mut this| {
                this.as_mut().set_channel_files_busy(false);
                match result {
                    Ok((op, v)) => {
                        if op == "shortcut" {
                            this.as_mut().set_status_text(QString::from(
                                "Added a shortcut in your OneDrive",
                            ));
                        }
                        this.as_mut()
                            .set_channel_files_json(QString::from(v.to_string().as_str()));
                    }
                    Err(e) => this
                        .as_mut()
                        .set_status_text(QString::from(short_error(&e).as_str())),
                }
            });
        });
    }

    pub fn onenote_load(mut self: Pin<&mut Self>, view: &QString, id: &QString) {
        let (view, id) = (view.to_string(), id.to_string());
        self.as_mut().set_onenote_busy(true);
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let c = TeamsClient::new().await?;
                let mut out = json!({ "view": view, "id": id });
                match view.as_str() {
                    "sections" => out["sections"] = json!(api::onenote::sections(&c, &id).await?),
                    "pages" => out["pages"] = json!(api::onenote::pages(&c, &id).await?),
                    "page" => out["html"] = json!(api::onenote::page_html(&c, &id).await?),
                    _ => out["notebooks"] = json!(api::onenote::notebooks(&c).await?),
                }
                anyhow::Ok(out)
            }
            .await;
            let _ = qt.queue(move |mut this| {
                this.as_mut().set_onenote_busy(false);
                let text = match result {
                    Ok(v) => v.to_string(),
                    Err(e) => json!({ "error": short_error(&e) }).to_string(),
                };
                this.as_mut().set_onenote_json(QString::from(text.as_str()));
            });
        });
    }

    pub fn onenote_create(
        mut self: Pin<&mut Self>,
        kind: &QString,
        parent: &QString,
        name: &QString,
        text: &QString,
    ) {
        let (kind, parent, name, text) = (
            kind.to_string(),
            parent.to_string(),
            name.to_string(),
            text.to_string(),
        );
        self.as_mut().set_onenote_busy(true);
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let c = TeamsClient::new().await?;
                let made = match kind.as_str() {
                    "notebook" => json!({ "view": "created", "kind": kind, "item": api::onenote::create_notebook(&c, &name).await? }),
                    "section" => json!({ "view": "created", "kind": kind, "parent": parent, "item": api::onenote::create_section(&c, &parent, &name).await? }),
                    _ => json!({ "view": "created", "kind": "page", "parent": parent, "item": api::onenote::create_page(&c, &parent, &name, &text).await? }),
                };
                anyhow::Ok(made)
            }
            .await;
            let _ = qt.queue(move |mut this| {
                this.as_mut().set_onenote_busy(false);
                match result {
                    // The view reloads what it shows from "created".
                    Ok(v) => this.as_mut().set_onenote_json(QString::from(v.to_string().as_str())),
                    Err(e) => this.as_mut().set_status_text(QString::from(short_error(&e).as_str())),
                }
            });
        });
    }

    pub fn onenote_delete_page(mut self: Pin<&mut Self>, id: &QString) {
        let id = id.to_string();
        self.as_mut().set_onenote_busy(true);
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result =
                async { api::onenote::delete_page(&TeamsClient::new().await?, &id).await }.await;
            let _ = qt.queue(move |mut this| {
                this.as_mut().set_onenote_busy(false);
                match result {
                    Ok(()) => this.as_mut().set_onenote_json(QString::from(
                        json!({ "view": "deleted", "id": id }).to_string().as_str(),
                    )),
                    Err(e) => this
                        .as_mut()
                        .set_status_text(QString::from(short_error(&e).as_str())),
                }
            });
        });
    }

    pub fn contacts_load(mut self: Pin<&mut Self>) {
        self.as_mut().set_contacts_busy(true);
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                let contacts = api::contacts::list(&client).await?;
                // Categories are a nicety; a mailbox without them still lists contacts.
                let categories = api::contacts::categories(&client).await.unwrap_or_default();
                anyhow::Ok(json!({ "contacts": contacts, "categories": categories }))
            }
            .await;
            let _ = qt.queue(move |mut this| {
                this.as_mut().set_contacts_busy(false);
                let text = match result {
                    Ok(v) => v.to_string(),
                    Err(e) => json!({ "error": short_error(&e) }).to_string(),
                };
                this.as_mut()
                    .set_contacts_json(QString::from(text.as_str()));
            });
        });
    }

    /// Run a contacts change, then reload.
    fn contacts_change<F, Fut>(mut self: Pin<&mut Self>, f: F)
    where
        F: FnOnce(TeamsClient) -> Fut + Send + 'static,
        Fut: std::future::Future<Output = anyhow::Result<()>> + Send,
    {
        self.as_mut().set_contacts_busy(true);
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async { f(TeamsClient::new().await?).await }.await;
            let _ = qt.queue(move |mut this| match result {
                Ok(()) => this.as_mut().contacts_load(),
                Err(e) => {
                    this.as_mut().set_contacts_busy(false);
                    this.as_mut()
                        .set_status_text(QString::from(short_error(&e).as_str()));
                }
            });
        });
    }

    pub fn contacts_add(self: Pin<&mut Self>, contact_json: &QString) {
        let text = contact_json.to_string();
        self.contacts_change(move |c| async move {
            let new: api::contacts::NewContact = serde_json::from_str(&text)?;
            api::contacts::create(&c, &new).await.map(|_| ())
        });
    }

    pub fn contacts_favorite(self: Pin<&mut Self>, id: &QString, on: bool) {
        let id = id.to_string();
        self.contacts_change(
            move |c| async move { api::contacts::set_favorite(&c, &id, on).await },
        );
    }

    pub fn contacts_delete(self: Pin<&mut Self>, id: &QString) {
        let id = id.to_string();
        self.contacts_change(move |c| async move { api::contacts::delete(&c, &id).await });
    }

    pub fn planner_load(mut self: Pin<&mut Self>, view: &QString, plan_json: &QString) {
        let (view, plan_json) = (view.to_string(), plan_json.to_string());
        self.as_mut().rust_mut().planner_view = (view.clone(), plan_json.clone());
        self.as_mut().set_planner_busy(true);
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                let mut out = json!({ "view": view });
                match view.as_str() {
                    "plans" => out["plans"] = json!(api::planner::plans(&client).await?),
                    "plan" => {
                        let v: serde_json::Value = serde_json::from_str(&plan_json)?;
                        let plan = api::planner::Plan {
                            id: v["id"].as_str().unwrap_or_default().to_string(),
                            title: v["title"].as_str().unwrap_or_default().to_string(),
                            group_id: v["group_id"].as_str().unwrap_or_default().to_string(),
                            team: v["team"].as_str().unwrap_or_default().to_string(),
                        };
                        out["tasks"] = json!(api::planner::plan_tasks(&client, &plan).await?);
                        out["plan"] = v;
                    }
                    _ => out["tasks"] = json!(api::planner::my_tasks(&client).await?),
                }
                anyhow::Ok(out)
            }
            .await;
            let _ = qt.queue(move |mut this| {
                this.as_mut().set_planner_busy(false);
                let text = match result {
                    Ok(v) => v.to_string(),
                    Err(e) => json!({ "error": short_error(&e) }).to_string(),
                };
                this.as_mut().set_planner_json(QString::from(text.as_str()));
            });
        });
    }

    fn planner_reload(mut self: Pin<&mut Self>) {
        let (v, p) = self.rust().planner_view.clone();
        self.as_mut()
            .planner_load(&QString::from(v.as_str()), &QString::from(p.as_str()));
    }

    /// Run a Planner change, then reload the view.
    fn planner_change<F, Fut>(mut self: Pin<&mut Self>, f: F)
    where
        F: FnOnce(TeamsClient) -> Fut + Send + 'static,
        Fut: std::future::Future<Output = anyhow::Result<()>> + Send,
    {
        self.as_mut().set_planner_busy(true);
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async { f(TeamsClient::new().await?).await }.await;
            let _ = qt.queue(move |mut this| match result {
                Ok(()) => this.as_mut().planner_reload(),
                Err(e) => {
                    this.as_mut().set_planner_busy(false);
                    this.as_mut()
                        .set_status_text(QString::from(short_error(&e).as_str()));
                }
            });
        });
    }

    pub fn planner_add(self: Pin<&mut Self>, title: &QString, due: &QString) {
        let (title, due) = (title.to_string(), due.to_string());
        self.planner_change(move |c| async move {
            api::planner::add_private_task(&c, &title, &due)
                .await
                .map(|_| ())
        });
    }

    pub fn planner_create_plan(
        self: Pin<&mut Self>,
        group_id: &QString,
        team: &QString,
        title: &QString,
    ) {
        let (g, t, title) = (group_id.to_string(), team.to_string(), title.to_string());
        self.planner_change(move |c| async move {
            api::planner::create_plan(&c, &g, &t, &title)
                .await
                .map(|_| ())
        });
    }

    pub fn planner_add_to_plan(self: Pin<&mut Self>, plan_json: &QString, title: &QString) {
        let (pj, title) = (plan_json.to_string(), title.to_string());
        self.planner_change(move |c| async move {
            let v: serde_json::Value = serde_json::from_str(&pj)?;
            let plan = api::planner::Plan {
                id: v["id"].as_str().unwrap_or_default().to_string(),
                title: v["title"].as_str().unwrap_or_default().to_string(),
                group_id: v["group_id"].as_str().unwrap_or_default().to_string(),
                team: v["team"].as_str().unwrap_or_default().to_string(),
            };
            api::planner::add_plan_task(&c, &plan, &title).await
        });
    }

    pub fn planner_delete_plan(self: Pin<&mut Self>, plan_id: &QString) {
        let id = plan_id.to_string();
        self.planner_change(move |c| async move { api::planner::delete_plan(&c, &id).await });
    }

    pub fn planner_complete(self: Pin<&mut Self>, task_json: &QString) {
        let Ok(task) = serde_json::from_str::<api::planner::Task>(&task_json.to_string()) else {
            return;
        };
        self.planner_change(move |c| async move { api::planner::complete(&c, &task).await });
    }

    pub fn planner_delete(self: Pin<&mut Self>, task_json: &QString) {
        let Ok(task) = serde_json::from_str::<api::planner::Task>(&task_json.to_string()) else {
            return;
        };
        self.planner_change(
            move |c| async move { api::planner::delete_private_task(&c, &task).await },
        );
    }

    pub fn drive_load(
        mut self: Pin<&mut Self>,
        view: &QString,
        drive_id: &QString,
        item_id: &QString,
    ) {
        let (view, drive_id, item_id) =
            (view.to_string(), drive_id.to_string(), item_id.to_string());
        self.as_mut().rust_mut().drive_view = (view.clone(), drive_id.clone(), item_id.clone());
        self.as_mut().set_drive_busy(true);
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                let mut out = json!({ "view": view, "drive_id": drive_id, "item_id": item_id });
                match view.as_str() {
                    "recent" => out["items"] = json!(api::drive::recent(&client).await?),
                    "shared" => out["items"] = json!(api::drive::shared_with_me(&client).await?),
                    "libraries" => out["libraries"] = json!(api::drive::libraries(&client).await?),
                    "favorites" => out["items"] = json!(api::drive::favorites(&client).await?),
                    "media" => out["items"] = json!(api::drive::media(&client).await?),
                    "meetings" => out["items"] = json!(api::drive::meetings(&client).await?),
                    "recycle" => out["deleted"] = json!(api::drive::recycle_bin(&client).await?),
                    "people" => {
                        out["people"] = json!(
                            api::drive::by_people(&client)
                                .await?
                                .into_iter()
                                .map(|(name, items)| json!({ "name": name, "items": items }))
                                .collect::<Vec<_>>()
                        )
                    }
                    _ => {
                        out["items"] =
                            json!(api::drive::children(&client, &drive_id, &item_id).await?)
                    }
                }
                // Teams' columns from SharePoint's rows (friendly Modified,
                // Sharing, the "new" mark, Activity); other views word
                // Graph's times the same way.
                let rows = if view == "folder" {
                    api::list_rows::for_folder(&client, &drive_id, &item_id)
                        .await
                        .unwrap_or_else(|e| {
                            tracing::warn!("OneDrive rows: {e:#}");
                            Default::default()
                        })
                } else {
                    Default::default()
                };
                if let Some(items) = out.get("items").cloned() {
                    let now = chrono::Local::now();
                    let items: Vec<api::drive::DriveItem> =
                        serde_json::from_value(items).unwrap_or_default();
                    out["items"] = json!(items
                        .iter()
                        .map(|it| api::list_rows::decorate(it, rows.get(&it.sp_item.to_ascii_lowercase()), now))
                        .collect::<Vec<_>>());
                }
                // Which items are favorites (the menu's Add to / Remove
                // from favorites).
                if out.get("items").is_some() {
                    out["favorite_ids"] = json!(api::drive::favorites(&client)
                        .await
                        .unwrap_or_default()
                        .into_iter()
                        .map(|f| f.id)
                        .collect::<Vec<_>>());
                }
                anyhow::Ok(out)
            }
            .await;
            let _ = qt.queue(move |mut this| {
                this.as_mut().set_drive_busy(false);
                let text = match result {
                    Ok(v) => v.to_string(),
                    Err(e) => json!({ "error": short_error(&e) }).to_string(),
                };
                this.as_mut().set_drive_json(QString::from(text.as_str()));
            });
        });
    }

    /// Reload the OneDrive view shown (after a change).
    fn drive_reload(mut self: Pin<&mut Self>) {
        let (v, d, i) = self.rust().drive_view.clone();
        self.as_mut().drive_load(
            &QString::from(v.as_str()),
            &QString::from(d.as_str()),
            &QString::from(i.as_str()),
        );
    }

    pub fn drive_download(mut self: Pin<&mut Self>, item_json: &QString) {
        let Ok(item) = serde_json::from_str::<api::drive::DriveItem>(&item_json.to_string()) else {
            return;
        };
        let Some(dir) = download_dir() else { return };
        self.as_mut().set_status_text(QString::from(
            format!("Downloading {}…", item.name).as_str(),
        ));
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                api::drive::download(&client, &item, &dir).await
            }
            .await;
            let msg = match result {
                Ok(path) => format!(
                    "Saved {} to {}",
                    item.name,
                    path.parent()
                        .map(|p| p.display().to_string())
                        .unwrap_or_default()
                ),
                Err(e) => short_error(&e),
            };
            let _ = qt
                .queue(move |mut this| this.as_mut().set_status_text(QString::from(msg.as_str())));
        });
    }

    pub fn drive_upload(
        mut self: Pin<&mut Self>,
        drive_id: &QString,
        folder_id: &QString,
        paths: &QString,
    ) {
        let (drive_id, folder_id) = (drive_id.to_string(), folder_id.to_string());
        let paths: Vec<std::path::PathBuf> = paths
            .to_string()
            .lines()
            .map(str::trim)
            .filter(|p| !p.is_empty())
            .map(std::path::PathBuf::from)
            .collect();
        if paths.is_empty() {
            return;
        }
        self.as_mut().set_status_text(QString::from(
            format!("Uploading {} file(s)…", paths.len()).as_str(),
        ));
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                for p in &paths {
                    api::drive::upload(&client, &drive_id, &folder_id, p).await?;
                }
                anyhow::Ok(paths.len())
            }
            .await;
            let _ = qt.queue(move |mut this| match result {
                Ok(n) => {
                    this.as_mut()
                        .set_status_text(QString::from(format!("Uploaded {n} file(s)").as_str()));
                    this.as_mut().drive_reload();
                }
                Err(e) => this
                    .as_mut()
                    .set_status_text(QString::from(short_error(&e).as_str())),
            });
        });
    }

    /// Run a OneDrive change, then reload the view shown.
    fn drive_change<F, Fut>(mut self: Pin<&mut Self>, f: F)
    where
        F: FnOnce(TeamsClient) -> Fut + Send + 'static,
        Fut: std::future::Future<Output = anyhow::Result<()>> + Send,
    {
        self.as_mut().set_drive_busy(true);
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async { f(TeamsClient::new().await?).await }.await;
            let _ = qt.queue(move |mut this| match result {
                Ok(()) => this.as_mut().drive_reload(),
                Err(e) => {
                    this.as_mut().set_drive_busy(false);
                    this.as_mut()
                        .set_status_text(QString::from(short_error(&e).as_str()));
                }
            });
        });
    }

    pub fn drive_favorite(self: Pin<&mut Self>, drive_id: &QString, item_id: &QString, on: bool) {
        let (d, i) = (drive_id.to_string(), item_id.to_string());
        self.drive_change(move |c| async move { api::drive::set_favorite(&c, &d, &i, on).await });
    }

    pub fn drive_restore(self: Pin<&mut Self>, ids: &QString) {
        let ids: Vec<String> = ids
            .to_string()
            .split(',')
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
            .collect();
        self.drive_change(move |c| async move { api::drive::restore(&c, &ids).await });
    }

    pub fn drive_purge(self: Pin<&mut Self>, ids: &QString) {
        let ids: Vec<String> = ids
            .to_string()
            .split(',')
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
            .collect();
        self.drive_change(move |c| async move { api::drive::purge(&c, &ids).await });
    }

    pub fn drive_new_folder(
        mut self: Pin<&mut Self>,
        drive_id: &QString,
        parent_id: &QString,
        name: &QString,
    ) {
        let (drive_id, parent_id, name) = (
            drive_id.to_string(),
            parent_id.to_string(),
            name.to_string(),
        );
        let qt = self.qt_thread();
        self.as_mut().set_drive_busy(true);
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                api::drive::new_folder(&client, &drive_id, &parent_id, &name).await
            }
            .await;
            let _ = qt.queue(move |mut this| match result {
                Ok(_) => this.as_mut().drive_reload(),
                Err(e) => {
                    this.as_mut().set_drive_busy(false);
                    this.as_mut()
                        .set_status_text(QString::from(short_error(&e).as_str()));
                }
            });
        });
    }

    pub fn drive_delete(mut self: Pin<&mut Self>, drive_id: &QString, item_id: &QString) {
        let (drive_id, item_id) = (drive_id.to_string(), item_id.to_string());
        let qt = self.qt_thread();
        self.as_mut().set_drive_busy(true);
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                api::drive::delete(&client, &drive_id, &item_id).await
            }
            .await;
            let _ = qt.queue(move |mut this| match result {
                Ok(()) => this.as_mut().drive_reload(),
                Err(e) => {
                    this.as_mut().set_drive_busy(false);
                    this.as_mut()
                        .set_status_text(QString::from(short_error(&e).as_str()));
                }
            });
        });
    }

    pub fn drive_action(self: Pin<&mut Self>, op: &QString, item_json: &QString, args_json: &QString) {
        let op = op.to_string();
        let item: api::drive::DriveItem = serde_json::from_str(&item_json.to_string()).unwrap_or_default();
        let args: serde_json::Value = serde_json::from_str(&args_json.to_string()).unwrap_or(json!({}));
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let s = |k: &str| args[k].as_str().unwrap_or_default().to_string();
            let sp = api::sharing::ItemRef { site: item.sp_site.clone(), list: item.sp_list.clone(), item: item.sp_item.clone() };
            // "<tag>:<op>": each Files view takes only its own replies.
            let kind = op.rsplit(':').next().unwrap_or_default().to_string();
            let result: anyhow::Result<serde_json::Value> = async {
                let client = TeamsClient::new().await?;
                Ok(match kind.as_str() {
                    "libraries" => json!(api::drive::libraries(&client).await?),
                    "rename" => {
                        api::drive::rename(&client, &item.drive_id, &item.id, &s("name")).await?;
                        json!(null)
                    }
                    "move" | "copy" | "duplicate" => {
                        // The item, and any others selected with it ("more").
                        let more: Vec<api::drive::DriveItem> =
                            serde_json::from_value(args["more"].clone()).unwrap_or_default();
                        let all: Vec<&api::drive::DriveItem> = std::iter::once(&item).chain(more.iter()).collect();
                        let mut sources = Vec::new();
                        for it in &all {
                            let r = api::sharing::ItemRef { site: it.sp_site.clone(), list: it.sp_list.clone(), item: it.sp_item.clone() };
                            sources.push(api::copy_jobs::absolute_url(&r).await?);
                        }
                        let (dest, names) = if kind == "duplicate" {
                            let parent = sources[0].rsplit_once('/').map(|(p, _)| p.to_string()).unwrap_or_default();
                            (parent, all.iter().map(|it| api::copy_jobs::duplicate_name(&it.name, it.is_folder)).collect())
                        } else {
                            (api::copy_jobs::folder_url(&s("dest")), Vec::new())
                        };
                        api::copy_jobs::run(&sp.site, &sources, &dest, kind == "move", &names).await?;
                        json!(null)
                    }
                    "open_app" => json!({ "path": api::drive::local_copy(&client, &item).await?.display().to_string() }),
                    "folders" => {
                        let (d, i) = (s("drive_id"), s("item_id"));
                        let (here, items) = tokio::join!(
                            async {
                                if i.is_empty() {
                                    api::drive::root(&client, &d).await
                                } else {
                                    api::drive::item(&client, &d, &i).await
                                }
                            },
                            api::drive::children(&client, &d, &i)
                        );
                        json!({ "drive_id": d, "item_id": i, "here": here?, "items": items? })
                    }
                    other => anyhow::bail!("unknown drive action {other}"),
                })
            }
            .await;
            let (value, error) = match result {
                Ok(v) => (v.to_string(), String::new()),
                Err(e) => {
                    tracing::warn!("drive {op}: {}", short_error(&e));
                    (String::new(), short_error(&e))
                }
            };
            let _ = qt.queue(move |mut this| this.as_mut().drive_action_done(QString::from(op.as_str()), QString::from(value.as_str()), QString::from(error.as_str())));
        });
    }

    pub fn update_event(
        mut self: Pin<&mut Self>,
        id: &QString,
        subject: &QString,
        start_utc: &QString,
        end_utc: &QString,
    ) {
        let (id, subject, start, end) = (
            id.to_string(),
            subject.to_string(),
            start_utc.to_string(),
            end_utc.to_string(),
        );
        self.as_mut().set_status_text(QString::from("Saving…"));
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                api::calendar::update_event(&client, &id, &subject, &start, &end).await
            }
            .await;
            let _ = qt.queue(move |mut this| match result {
                Ok(()) => {
                    this.as_mut().set_status_text(QString::default());
                    this.as_mut().refresh_calendar();
                }
                Err(e) => this
                    .as_mut()
                    .set_status_text(QString::from(short_error(&e).as_str())),
            });
        });
    }

    pub fn delete_event(mut self: Pin<&mut Self>, id: &QString) {
        let id = id.to_string();
        self.as_mut().set_status_text(QString::from("Deleting…"));
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                api::calendar::delete_event(&client, &id).await
            }
            .await;
            let _ = qt.queue(move |mut this| match result {
                Ok(()) => {
                    this.as_mut().set_status_text(QString::default());
                    this.as_mut().refresh_calendar();
                }
                Err(e) => this
                    .as_mut()
                    .set_status_text(QString::from(short_error(&e).as_str())),
            });
        });
    }

    pub fn create_event(
        mut self: Pin<&mut Self>,
        subject: &QString,
        start_utc: &QString,
        end_utc: &QString,
        attendees: &QString,
        teams_meeting: bool,
    ) {
        let (subject, start, end) = (
            subject.to_string(),
            start_utc.to_string(),
            end_utc.to_string(),
        );
        let attendees: Vec<String> = attendees
            .to_string()
            .split([',', ';'])
            .map(|a| a.trim().to_string())
            .filter(|a| !a.is_empty())
            .collect();
        self.as_mut().set_status_text(QString::from("Scheduling…"));
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                api::calendar::create_event(
                    &client,
                    &subject,
                    &start,
                    &end,
                    &attendees,
                    teams_meeting,
                )
                .await
            }
            .await;
            let _ = qt.queue(move |mut this| match result {
                Ok(ev) => {
                    this.as_mut().set_status_text(QString::from(
                        format!("Scheduled {}", ev.subject).as_str(),
                    ));
                    this.as_mut().refresh_calendar();
                }
                Err(e) => this
                    .as_mut()
                    .set_status_text(QString::from(short_error(&e).as_str())),
            });
        });
    }

    pub fn reload_teams(self: Pin<&mut Self>) {
        self.load_teams();
    }

    pub fn mark_all_read(mut self: Pin<&mut Self>) {
        let ids: Vec<String> = self.as_mut().rust_mut().unread.drain().collect();
        self.as_mut().publish_chats();
        if ids.is_empty() {
            return;
        }
        runtime().spawn(async move {
            let Ok(client) = TeamsClient::new().await else {
                return;
            };
            for id in ids {
                if let Err(e) = api::messages::mark_chat_read_to_latest(&client, &id).await {
                    tracing::debug!("mark read failed: {}", short_error(&e));
                }
            }
            tracing::info!("marked all read");
        });
    }

    pub fn set_my_status(self: Pin<&mut Self>, status: &QString) {
        // Teams' default duration is Today (Reset has none).
        self.set_my_status_until(status, &QString::from("Today"), &QString::default());
    }

    /// Set your status as Teams does (forceavailability with
    /// desiredExpirationTime from the Duration choice; Custom takes an ISO
    /// local time), dropping repeats as Teams' manager does.
    pub fn set_my_status_until(
        mut self: Pin<&mut Self>,
        status: &QString,
        duration: &QString,
        custom: &QString,
    ) {
        use std::sync::Mutex;
        // (availability, duration) of the last request, when it was sent, and
        // whether it is still pending.
        static LAST: Mutex<Option<(String, String, std::time::Instant, bool)>> = Mutex::new(None);
        let status = status.to_string();
        let duration = duration.to_string();
        let custom = custom.to_string();
        // A custom end is part of the choice (Pause notifications' 10
        // minutes twice is two different ends).
        let choice = format!("{duration}|{custom}");
        {
            let last = LAST.lock().unwrap();
            if let Some((a, d, at, pending)) = last.as_ref() {
                let same = *a == status && *d == choice;
                // Identical while in flight, any request within 10 s of a
                // pending one, or equal to the current one within 300 s.
                if (*pending && (same || at.elapsed().as_secs() < 10))
                    || (same && at.elapsed().as_secs() < 300)
                {
                    return;
                }
            }
        }
        *LAST.lock().unwrap() = Some((
            status.clone(),
            choice,
            std::time::Instant::now(),
            true,
        ));
        let forced = (status != "Reset").then(|| status.clone());
        if let (Some(f), Some(me)) = (forced.clone(), self.rust().my_mri.clone()) {
            self.as_mut().rust_mut().presence.insert(me, f);
            self.as_mut().publish_chats();
        }
        let until = if duration == "Custom" {
            chrono::DateTime::parse_from_rfc3339(&custom)
                .ok()
                .map(|t| t.with_timezone(&chrono::Local))
        } else {
            teams_cli::api::presence::expiry_for(&duration, chrono::Local::now())
        };
        let until = forced.as_ref().and(until);
        let until_iso = until
            .map(|t| t.with_timezone(&chrono::Utc).to_rfc3339_opts(chrono::SecondsFormat::Millis, true))
            .unwrap_or_default();
        self.as_mut().set_my_status_ends(QString::from(until_iso.as_str()));
        let me = self.rust().my_mri.clone();
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let http = reqwest::Client::new();
            let sent = teams_cli::api::presence::force_availability_until(&http, forced.as_deref(), until).await;
            if let Err(e) = &sent {
                tracing::warn!("set status failed: {}", short_error(e));
            }
            if let Some(l) = LAST.lock().unwrap().as_mut() {
                l.3 = false;
            }
            // Reset: your status is what your activity says again, so
            // read it back now rather than at the next refresh.
            if sent.is_ok()
                && forced.is_none()
                && let Some(me) = me
                && let Ok(list) = teams_cli::api::presence::get_presences(&http, std::slice::from_ref(&me)).await
                && let Some(p) = list.into_iter().next()
            {
                let _ = qt.queue(move |mut this| {
                    this.as_mut().set_my_status_ends(QString::from(p.forced_until.as_str()));
                    this.as_mut().rust_mut().presence.insert(p.mri, p.availability);
                    this.as_mut().publish_chats();
                });
            }
        });
    }

    /// Set your status message (Teams' publishnote): `message`, shown when
    /// people message you if `pinned`, cleared after `clear_after` (Never,
    /// Today, OneHour, FourHours, ThisWeek, or Custom with `custom`).
    pub fn set_status_note(
        self: Pin<&mut Self>,
        message: &QString,
        pinned: bool,
        clear_after: &QString,
        custom: &QString,
    ) {
        let (message, choice, custom) = (
            message.to_string(),
            clear_after.to_string(),
            custom.to_string(),
        );
        let until = if choice == "Custom" {
            chrono::DateTime::parse_from_rfc3339(&custom)
                .ok()
                .map(|t| t.with_timezone(&chrono::Local))
        } else {
            teams_cli::api::presence::expiry_for(&choice, chrono::Local::now())
        };
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let http = reqwest::Client::new();
            let result =
                teams_cli::api::presence::publish_note(&http, &message, pinned, until).await;
            let _ = qt.queue(move |mut this| {
                // Yours as the presence service will now say (Never is the
                // year 9999).
                if result.is_ok() {
                    let cleared = message.trim().is_empty();
                    let note = json!({
                        "text": if cleared { String::new() } else { teams_cli::api::presence::note_plain(&message) },
                        "html": if cleared { String::new() } else { teams_cli::api::messages::sanitize_html_marking(&teams_cli::api::presence::note_html_any(&message), &[]) },
                        "pinned": pinned && !cleared,
                        "expiry": if cleared { String::new() } else { until.map(|t| t.with_timezone(&chrono::Utc).to_rfc3339_opts(chrono::SecondsFormat::Millis, true)).unwrap_or_else(|| "9999-12-31T23:59:59.999Z".into()) },
                    })
                    .to_string();
                    this.as_mut().set_my_note_json(QString::from(note.as_str()));
                }
                let text = match &result {
                    Ok(()) => json!({
                        "ok": true,
                        "message": teams_cli::api::presence::note_plain(&message),
                        "html": if message.trim().is_empty() { String::new() } else { teams_cli::api::messages::sanitize_html_marking(&teams_cli::api::presence::note_html_any(&message), &[]) },
                        "pinned": pinned,
                    }),
                    Err(e) => json!({ "ok": false, "error": short_error(e) }),
                };
                this.as_mut()
                    .set_status_note_result(QString::from(text.to_string().as_str()));
            });
        });
    }

    pub fn audio_devices(self: Pin<&mut Self>) -> QString {
        let (inputs, outputs) = teams_cli::calling::audio::list_devices();
        let (default_input, default_output) = teams_cli::calling::audio::default_devices();
        QString::from(
            json!({ "inputs": inputs, "outputs": outputs, "defaultInput": default_input, "defaultOutput": default_output })
                .to_string()
                .as_str(),
        )
    }

    pub fn speaker_volume(self: Pin<&mut Self>) -> i32 {
        teams_cli::calling::audio::speaker_volume() as i32
    }

    pub fn set_speaker_volume(self: Pin<&mut Self>, volume: i32) {
        teams_cli::calling::audio::set_speaker_volume(volume.clamp(0, 100) as u32);
    }

    pub fn mic_level(self: Pin<&mut Self>) -> i32 {
        teams_cli::calling::audio::mic_level() as i32
    }

    pub fn request_profile(self: Pin<&mut Self>, mri: &QString) {
        self.profile_requested(mri.clone());
    }

    pub fn load_profile_card(mut self: Pin<&mut Self>, who: &QString) {
        let who = who.to_string();
        let oid = who.trim_start_matches("8:orgid:").to_string();
        self.as_mut().set_profile_card_json(QString::from(json!({ "id": oid, "loading": true }).to_string().as_str()));
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                let mut card = api::profile::profile_card(&client, &oid).await?;
                let http = reqwest::Client::new();
                if let Ok(list) = teams_cli::api::presence::get_presences(&http, &[format!("8:orgid:{oid}")]).await
                    && let Some(p) = list.into_iter().next()
                {
                    card["presence"] = json!({
                        "availability": p.availability, "activity": p.activity, "lastActive": p.last_active,
                        "note": p.note_text, "noteHtml": p.note_html, "outOfOffice": p.out_of_office, "workLocation": p.work_location,
                    });
                }
                if let Some(start) = card["schedule"]["start"].as_str().and_then(|s| chrono::DateTime::parse_from_rfc3339(s).ok())
                    && let Some(view) = card["schedule"]["view"].as_str()
                {
                    card["schedule"]["nextFree"] = json!(api::profile::next_free(view, start.with_timezone(&chrono::Utc)).map(|t| t.to_rfc3339()));
                }
                anyhow::Ok(card)
            }
            .await;
            let _ = qt.queue(move |mut this| {
                let v = match result {
                    Ok(c) => c,
                    Err(e) => json!({ "id": oid, "error": short_error(&e) }),
                };
                this.as_mut().set_profile_card_json(QString::from(v.to_string().as_str()));
            });
        });
    }

    pub fn test_notification(self: Pin<&mut Self>) {
        let prefs = notify_prefs(&self.rust().settings_json.to_string(), &load_settings());
        let body = if prefs.previews { "Message preview." } else { "Message preview hidden" };
        let timeout = prefs.seconds * 1000;
        let silent = !prefs.sound;
        std::thread::spawn(move || {
            let _ = notify_rust::Notification::new()
                .appname("OST")
                .summary("This is a test notification")
                .body(body)
                .icon("ost-desktop")
                .hint(notify_rust::Hint::Category("im.received".into()))
                .hint(notify_rust::Hint::SuppressSound(silent))
                .timeout(notify_rust::Timeout::Milliseconds(timeout))
                .show();
        });
    }

    pub fn office_app_name(self: Pin<&mut Self>) -> QString {
        QString::from(office_app().map(|(_, name)| name).unwrap_or_default().as_str())
    }

    pub fn open_file(self: Pin<&mut Self>, url: &QString, name: &QString, item_json: &QString) {
        let (url, name) = (url.to_string(), name.to_string());
        let item: Option<api::drive::DriveItem> =
            serde_json::from_str(&item_json.to_string()).ok().filter(|i: &api::drive::DriveItem| !i.id.is_empty());
        let desktop = load_settings().get("fileOpenIn").and_then(|v| v.as_str()) == Some("desktop");
        if !(desktop && is_office_file(&name) && office_app().is_some()) {
            if url.starts_with("https://") {
                let _ = std::process::Command::new("xdg-open").arg(&url).spawn();
            }
            return;
        }
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                let item = match item {
                    Some(i) => i,
                    None => api::drive::item_by_url(&client, &url).await?,
                };
                api::drive::local_copy(&client, &item).await
            }
            .await;
            match result {
                Ok(path) => {
                    let _ = std::process::Command::new("xdg-open").arg(&path).spawn();
                }
                Err(e) => {
                    let msg = format!("{name} didn't open: {}", short_error(&e));
                    let _ = qt.queue(move |mut this| this.as_mut().toast(&msg, "error"));
                }
            }
        });
    }

    pub fn download_location(self: Pin<&mut Self>) -> QString {
        QString::from(download_dir().map(|d| d.display().to_string()).unwrap_or_default().as_str())
    }

    pub fn load_settings(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                let props = api::preferences::all_properties(&client).await?;
                let mut mt = api::preferences::middle_tier_settings(&client).await.unwrap_or_else(|_| json!({}));
                if let Ok(oof) = api::preferences::automatic_replies(&client).await {
                    mt["oof"] = oof;
                }
                if let Ok(voice) = api::preferences::voice_settings(&client).await {
                    mt["voice"] = voice;
                }
                anyhow::Ok(json!({ "props": props, "mt": mt, "loaded": true }))
            }
            .await;
            let _ = qt.queue(move |mut this| match result {
                Ok(v) => this.as_mut().set_settings_json(QString::from(v.to_string().as_str())),
                Err(e) => {
                    tracing::warn!("settings unavailable: {}", short_error(&e));
                    this.as_mut().set_settings_error(QString::from(short_error(&e).as_str()));
                }
            });
        });
    }

    pub fn change_setting(mut self: Pin<&mut Self>, kind: &QString, name: &QString, value_json: &QString) {
        let (kind, name) = (kind.to_string(), name.to_string());
        let value: serde_json::Value = serde_json::from_str(&value_json.to_string()).unwrap_or(serde_json::Value::Null);
        // Shown at once; put back if the save fails.
        let before = self.rust().settings_json.to_string();
        let mut all: serde_json::Value = serde_json::from_str(&before).unwrap_or_else(|_| json!({ "props": {}, "mt": {} }));
        if kind == "mt" {
            all["mt"][&name] = value.clone();
        } else if value.is_object() {
            let base = all["props"].get(&name).cloned().unwrap_or_else(|| json!({}));
            all["props"][&name] = api::preferences::merged(base, &value);
        } else {
            all["props"][&name] = value.clone();
        }
        self.as_mut().set_settings_json(QString::from(all.to_string().as_str()));
        self.as_mut().set_settings_error(QString::default());
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                if kind == "mt" && name == "oof" {
                    api::preferences::set_automatic_replies(&client, &value).await?;
                    anyhow::Ok(None)
                } else if kind == "mt" && name == "redirection" {
                    let b = api::preferences::call_redirection_body(
                        value["forwardAll"].as_bool().unwrap_or(false),
                        value["unansweredToVoicemail"].as_bool().unwrap_or(true),
                        value["delay"].as_u64().unwrap_or(20) as u32,
                    );
                    api::preferences::set_voice_setting(&client, "redirection", &b).await?;
                    anyhow::Ok(None)
                } else if kind == "mt" && name == "voicemail" {
                    api::preferences::set_voice_setting(&client, "voicemail", &value).await?;
                    anyhow::Ok(None)
                } else if kind == "mt" {
                    api::preferences::set_middle_tier_setting(&client, &name, value.as_bool().unwrap_or(false)).await?;
                    anyhow::Ok(None)
                } else {
                    Ok(Some(api::preferences::set_property(&client, &name, &value).await?))
                }
            }
            .await;
            let _ = qt.queue(move |mut this| match result {
                Ok(Some(saved)) => {
                    let mut all: serde_json::Value = serde_json::from_str(&this.rust().settings_json.to_string()).unwrap_or_else(|_| json!({ "props": {}, "mt": {} }));
                    all["props"][&name] = saved;
                    this.as_mut().set_settings_json(QString::from(all.to_string().as_str()));
                }
                Ok(None) => {}
                Err(e) => {
                    tracing::warn!("setting {name} not saved: {}", short_error(&e));
                    this.as_mut().set_settings_json(QString::from(before.as_str()));
                    this.as_mut().set_settings_error(QString::from(name.as_str()));
                }
            });
        });
    }

    pub fn load_read_receipts(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                api::messages::read_receipts_enabled(&client).await
            }
            .await;
            match result {
                Ok(on) => {
                    let _ = qt.queue(move |mut this| this.as_mut().set_read_receipts(on));
                }
                Err(e) => tracing::warn!("read receipts setting: {}", short_error(&e)),
            }
        });
    }

    pub fn change_read_receipts(mut self: Pin<&mut Self>, on: bool) {
        self.as_mut().set_read_receipts(on);
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                api::messages::set_read_receipts_enabled(&client, on).await
            }
            .await;
            if let Err(e) = result {
                tracing::warn!("saving read receipts failed: {}", short_error(&e));
            }
        });
    }

    pub fn send_files(self: Pin<&mut Self>, paths: &QString, text: &QString) {
        let chat_id = self.rust().current_chat_id.to_string();
        self.send_files_in(chat_id.clone(), chat_id, paths, text);
    }

    /// Files into a thread window's thread: uploaded to the channel's
    /// folder, sent as a reply.
    pub fn send_thread_files(self: Pin<&mut Self>, channel_id: &QString, root_id: &QString, paths: &QString, text: &QString) {
        let (channel, root) = (channel_id.to_string(), root_id.to_string());
        if !channel.ends_with("@thread.tacv2") || root.is_empty() || !root.bytes().all(|b| b.is_ascii_digit()) {
            return;
        }
        let thread = format!("{channel};messageid={root}");
        self.send_files_in(channel, thread, paths, text);
    }

    /// Upload `paths` for `chat_id`'s files and send them, with `text`, to
    /// `conversation`.
    fn send_files_in(mut self: Pin<&mut Self>, chat_id: String, conversation: String, paths: &QString, text: &QString) {
        let text = text.to_string();
        let paths: Vec<std::path::PathBuf> = paths
            .to_string()
            .lines()
            .map(str::trim)
            .filter(|l| !l.is_empty())
            // QML hands over decoded local paths (file:// is tolerated).
            .map(|l| std::path::PathBuf::from(l.strip_prefix("file://").unwrap_or(l)))
            .collect();
        if chat_id.is_empty() || paths.is_empty() {
            return;
        }
        self.as_mut().set_busy(true);
        let names: Vec<String> = paths
            .iter()
            .filter_map(|p| p.file_name().and_then(|n| n.to_str()).map(str::to_string))
            .collect();
        self.as_mut().set_status_text(QString::from(
            format!("Uploading {}…", names.join(", ")).as_str(),
        ));
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                let mut files = Vec::new();
                for p in &paths {
                    files.push(api::files::upload_for_chat(&client, &chat_id, p).await?);
                }
                api::files::send_with_files(&client, &conversation, &text, files).await
            }
            .await;
            let sent_to = chat_id.clone();
            let _ = qt.queue(move |mut this| {
                this.as_mut().set_busy(false);
                match result {
                    Ok(()) => {
                        this.as_mut().set_status_text(QString::default());
                        this.as_mut().reload_where(&sent_to);
                    }
                    Err(e) => this
                        .as_mut()
                        .set_status_text(QString::from(short_error(&e).as_str())),
                }
            });
        });
    }

    pub fn send_rich(self: Pin<&mut Self>, editor_html: &QString) {
        self.send_rich_media(editor_html, &QString::default());
    }

    pub fn send_rich_media(self: Pin<&mut Self>, editor_html: &QString, media_json: &QString) {
        let mut media: Vec<api::messages::ComposeMedia> =
            serde_json::from_str(&media_json.to_string()).unwrap_or_default();
        // Captioned stickers are pictures we drew: upload them to AMS first.
        if media.iter().any(|m| m.kind == "image" && m.id.is_empty()) {
            let chat_id = self.rust().current_chat_id.to_string();
            let editor_html = editor_html.to_string();
            let qt = self.qt_thread();
            runtime().spawn(async move {
                let result = async {
                    let client = TeamsClient::new().await?;
                    let base = client.ams_url().context("No media store address")?;
                    for m in media.iter_mut().filter(|m| m.kind == "image" && m.id.is_empty()) {
                        let path = m.path.trim_start_matches("file://").to_string();
                        let bytes = std::fs::read(&path).context("Reading the sticker picture")?;
                        let id = client.ams_upload_image(&chat_id, bytes, "sticker.png").await?;
                        m.url = format!("{base}/v1/objects/{id}/views/imgo");
                        m.id = id;
                        let _ = std::fs::remove_file(&path);
                    }
                    anyhow::Ok(media)
                }
                .await;
                let _ = qt.queue(move |mut this| match result {
                    Ok(media) => {
                        let json = serde_json::to_string(&media.iter().map(|m| json!({"src": m.src, "kind": m.kind, "id": m.id, "title": m.title, "unicode": m.unicode, "url": m.url, "width": m.width, "height": m.height})).collect::<Vec<_>>()).unwrap_or_default();
                        this.as_mut().send_rich_media(&QString::from(editor_html.as_str()), &QString::from(json.as_str()));
                    }
                    Err(e) => this.as_mut().set_status_text(QString::from(
                        format!("Couldn't send the sticker: {}", short_error(&e)).as_str(),
                    )),
                });
            });
            return;
        }
        let (html, mentions) =
            api::messages::teams_html_with_media(&editor_html.to_string(), &media);
        let chat_id = self.rust().current_chat_id.to_string();
        if chat_id.is_empty() || html.trim().is_empty() {
            return;
        }
        let mentions = if mentions.is_empty() {
            String::new()
        } else {
            serde_json::to_string(&mentions).unwrap_or_default()
        };
        self.enqueue_with(chat_id, html, mentions);
    }

    pub fn download_file(mut self: Pin<&mut Self>, file_json: &QString) {
        let Ok(file) = serde_json::from_str::<api::files::FileAttachment>(&file_json.to_string())
        else {
            return;
        };
        let Some(dir) = download_dir() else { return };
        self.as_mut().set_status_text(QString::from(
            format!("Downloading {}…", file.name).as_str(),
        ));
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                api::files::download(&client, &file, &dir).await
            }
            .await;
            let msg = match result {
                Ok(path) => format!(
                    "Saved {} to {}",
                    file.name,
                    path.parent()
                        .map(|p| p.display().to_string())
                        .unwrap_or_default()
                ),
                Err(e) => short_error(&e),
            };
            let _ = qt
                .queue(move |mut this| this.as_mut().set_status_text(QString::from(msg.as_str())));
        });
    }

    pub fn refresh_receipts(self: Pin<&mut Self>) {
        let chat_id = self.rust().current_chat_id.to_string();
        if chat_id.is_empty() {
            return;
        }
        let shown = self.rust().messages_json.to_string();
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let horizon = async {
                let client = TeamsClient::new().await?;
                api::messages::peer_read_horizon(&client, &chat_id).await
            }
            .await;
            let horizon = match horizon {
                Ok(h) => h,
                Err(e) => {
                    tracing::debug!("read horizons unavailable: {}", short_error(&e));
                    return;
                }
            };
            let Ok(mut timeline) = serde_json::from_str::<Vec<api::messages::MessageView>>(&shown)
            else {
                return;
            };
            api::messages::apply_seen(&mut timeline, horizon);
            let Ok(json) = serde_json::to_string(&timeline) else {
                return;
            };
            if json == shown {
                return;
            }
            tracing::info!("read receipts changed");
            let _ = qt.queue(move |mut this| {
                // Only if the same chat is still open and unchanged meanwhile.
                if this.rust().current_chat_id.to_string() == chat_id
                    && this.rust().messages_json.to_string() == shown
                {
                    this.as_mut()
                        .set_messages_json(QString::from(json.as_str()));
                }
            });
        });
    }
}

#[cfg(test)]
mod toast_tests {
    use super::*;

    #[test]
    fn typing_reads_as_teams_says_it() {
        let n = |v: &[&str]| v.iter().map(|s| s.to_string()).collect::<Vec<_>>();
        assert_eq!(typing_text(&n(&["Ann"])), "Ann is typing");
        assert_eq!(typing_text(&n(&["Ann", "Bo"])), "Ann and Bo are typing");
        assert_eq!(
            typing_text(&n(&["Ann", "Bo", "Cy"])),
            "Ann, Bo, and Cy are typing"
        );
        assert_eq!(
            typing_text(&n(&["Ann", "Bo", "Cy", "Di", "Ed"])),
            "Ann, Bo, and 3 others are typing"
        );
    }

    #[test]
    fn toasts_follow_teams_presence_rule() {
        let none = serde_json::Map::new();
        let d = notify_prefs("{}", &none);
        assert!(!d.mute_all && d.chat_banners && d.previews && d.during_calls && d.sound && !d.meet_now && d.flash);
        assert_eq!(d.seconds, 5);
        let saved = r#"{"props":{"userPersonalSettings":{"toastSettings":{"muteGenericNotifications":"On","Chat":false,"ShowPreviewInToasts":"Off","MuteNotificationsDuringMeetings":"On","HuddleStartedNotification":true},"soundsSettings":{"alertSound":"Off"}}}}"#;
        let p = notify_prefs(saved, &none);
        assert!(p.mute_all && !p.chat_banners && !p.previews && !p.during_calls && !p.sound && p.meet_now);
        assert_eq!(toast_decision("Available", false, false), Toast::Show);
        assert_eq!(toast_decision("Busy", false, false), Toast::Show);
        assert_eq!(toast_decision("DoNotDisturb", false, false), Toast::Drop);
        assert_eq!(toast_decision("DoNotDisturb", false, true), Toast::Show);
        assert_eq!(toast_decision("DoNotDisturb", true, false), Toast::Drop);
        assert_eq!(toast_decision("Available", true, true), Toast::Redacted);
    }
}

#[cfg(test)]
mod tests {
    use super::{chat_muted, photo_target, should_notify};
    use serde_json::json;
    use teams_cli::api::directory::PhotoOwner;

    const OID: &str = "4287e791-1b98-4963-8b94-281c50472683";

    #[test]
    fn notifications_follow_teams_defaults() {
        // (mine, open, empty, banners, mentions_only, mentions_needed, mentioned)
        assert!(should_notify(
            false, false, false, true, false, false, false
        ));
        assert!(!should_notify(true, false, false, true, false, false, true));
        assert!(!should_notify(false, true, false, true, false, false, true));
        assert!(!should_notify(
            false, false, false, false, false, false, true
        ));
        // Channel posts: mentions only.
        assert!(!should_notify(
            false, false, false, true, false, true, false
        ));
        assert!(should_notify(false, false, false, true, false, true, true));
        // "Only mentions" setting.
        assert!(!should_notify(
            false, false, false, true, true, false, false
        ));
        assert!(should_notify(false, false, false, true, true, false, true));
        // Muted chats need a mention, as channel posts do.
        let chats = vec![
            json!({"id": "19:a@thread.v2", "muted": true}),
            json!({"id": "19:b@thread.v2"}),
        ];
        assert!(chat_muted(&chats, "19:a@thread.v2"));
        assert!(!chat_muted(&chats, "19:b@thread.v2"));
    }

    #[test]
    fn photo_targets_accept_only_object_ids() {
        assert_eq!(
            photo_target(&format!("8:orgid:{OID}"), None),
            Some((PhotoOwner::User, OID.to_string()))
        );
        assert_eq!(
            photo_target(&format!("team:{}", OID.to_uppercase()), None),
            Some((PhotoOwner::Team, OID.to_string()))
        );
        assert_eq!(
            photo_target("me", Some(OID)),
            Some((PhotoOwner::User, OID.to_string()))
        );
        assert_eq!(photo_target("me", None), None);
        // A guest is drawn by name, as Teams asks for their picture.
        assert_eq!(
            photo_target("8:teamsvisitor:43cf0b1e5a8d4c2f9e7f0a1b2c3d4e5f", None),
            Some((PhotoOwner::Named, String::new()))
        );
        // Anything that could change the request path is refused.
        assert_eq!(photo_target("../../me", None), None);
        assert_eq!(photo_target("8:orgid:abc?x=1", None), None);
        assert_eq!(photo_target(&format!("{OID}/x"), None), None);
    }
}

/// Word, PowerPoint and Excel files (Teams' setting names these three).
fn is_office_file(name: &str) -> bool {
    let ext = name.rsplit_once('.').map(|(_, e)| e.to_ascii_lowercase()).unwrap_or_default();
    matches!(ext.as_str(), "doc" | "docx" | "docm" | "dot" | "dotx" | "ppt" | "pptx" | "pptm" | "pps" | "ppsx" | "pot" | "potx" | "xls" | "xlsx" | "xlsm" | "xlsb" | "xlt" | "xltx")
}

/// The desktop's default app for Word files: its .desktop id and name
/// (`xdg-mime query default`, then the entry's Name).
fn office_app() -> Option<(String, String)> {
    static APP: std::sync::OnceLock<Option<(String, String)>> = std::sync::OnceLock::new();
    APP.get_or_init(|| {
        const DOCX: &str = "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
        let home = std::env::var("XDG_DATA_HOME")
            .ok()
            .or_else(|| std::env::var("HOME").ok().map(|h| format!("{h}/.local/share")));
        let dirs = std::env::var("XDG_DATA_DIRS").unwrap_or_else(|_| "/usr/local/share:/usr/share".into());
        let data: Vec<String> = home.into_iter().chain(dirs.split(':').map(str::to_string)).collect();
        // The chosen default, else the first app that says it opens Word
        // files (the MIME cache xdg-open falls back to).
        let chosen = std::process::Command::new("xdg-mime")
            .args(["query", "default", DOCX])
            .output()
            .ok()
            .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
            .filter(|id| id.ends_with(".desktop"));
        let id = chosen.or_else(|| {
            data.iter()
                .filter_map(|d| std::fs::read_to_string(format!("{d}/applications/mimeinfo.cache")).ok())
                .find_map(|text| {
                    text.lines()
                        .find_map(|l| l.strip_prefix(&format!("{DOCX}=")).and_then(|v| v.split(';').find(|x| !x.is_empty()).map(str::to_string)))
                })
        })?;
        let name = data
            .iter()
            .filter_map(|d| std::fs::read_to_string(format!("{d}/applications/{id}")).ok())
            .find_map(|text| {
                text.lines()
                    .find_map(|l| l.strip_prefix("Name=").map(|n| n.trim().to_string()))
            })
            .unwrap_or_else(|| id.trim_end_matches(".desktop").to_string());
        Some((id, name))
    })
    .clone()
}

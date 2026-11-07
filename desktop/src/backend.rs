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

unsafe extern "C" {
    /// Put text (and its HTML form) on the clipboard (src/native.cpp).
    fn ost_set_clipboard(text: *const core::ffi::c_char, html: *const core::ffi::c_char);
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
        /// The meeting's participants: [{id, name, role, active, server_muted}].
        #[qproperty(QString, call_roster_json)]
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
        #[qproperty(bool, call_has_audio)]
        /// "Randy Northrup is typing" for the open chat, or "".
        #[qproperty(QString, typing_text)]
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

        /// Answer the ringing call, with or without video.
        #[qinvokable]
        fn accept_call(self: Pin<&mut Backend>, with_video: bool);

        /// Decline the ringing call.
        #[qinvokable]
        fn decline_call(self: Pin<&mut Backend>);

        /// Call the other person in the open 1:1 chat.
        #[qinvokable]
        fn start_call(self: Pin<&mut Backend>);

        /// Join the Teams meeting with this join link; `title` is shown in
        /// the call window.
        #[qinvokable]
        fn join_meeting(self: Pin<&mut Backend>, join_url: &QString, title: &QString);

        /// End the current call.
        #[qinvokable]
        fn hang_up(self: Pin<&mut Backend>);

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

        /// Delete one of our messages in the open chat.
        #[qinvokable]
        fn delete_message(self: Pin<&mut Backend>, message_id: &QString);

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

        /// A profile or team picture asked for with photo_for is ready.
        #[qsignal]
        fn photo_ready(self: Pin<&mut Backend>, id: QString);

        /// The picture for "me", a user ("8:orgid:<oid>" or "<oid>") or a
        /// team ("team:<group id>"): a file URL, or "" for initials. Starts
        /// a download when needed and signals photo_ready when it lands.
        #[qinvokable]
        fn photo_for(self: Pin<&mut Backend>, id: &QString, name: &QString) -> QString;

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

        /// Save an app setting.
        #[qinvokable]
        fn set_setting(self: Pin<&mut Backend>, name: &QString, value: &QString);

        /// Reply to a post in the open channel (`root_id` is the post's id).
        #[qinvokable]
        fn send_reply(self: Pin<&mut Backend>, root_id: &QString, text: &QString);

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

        /// A channel's tabs (Page, Notes, apps) into channel_tabs_json.
        #[qinvokable]
        fn channel_tabs_load(
            self: Pin<&mut Backend>,
            team_id: &QString,
            channel_id: &QString,
            channel_name: &QString,
        );

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
        /// "remove" tab `tab_id`; the outcome goes to channelTabResult and
        /// the tabs reload.
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

        /// Set your status ("Available", "Busy", "DoNotDisturb",
        /// "BeRightBack", "Away", "Offline"), or "Reset".
        #[qinvokable]
        fn set_my_status(self: Pin<&mut Backend>, status: &QString);

        /// Microphones and speakers: {"inputs": [...], "outputs": [...]}.
        #[qinvokable]
        fn audio_devices(self: Pin<&mut Backend>) -> QString;

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
    call_thread_id: QString,
    user_mri: QString,
    roster: Vec<teams_cli::calling::roster::Participant>,
    call_muted: bool,
    call_held: bool,
    call_held_by_peer: bool,
    call_can_dtmf: bool,
    call_can_share: bool,
    call_sharing: bool,
    call_hand_raised: bool,
    call_options_url: QString,
    call_chat_url: QString,
    call_has_audio: bool,
    typing_text: QString,
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
    teams_json: QString,
    people_query_generation: u64,
    /// Bumped on every typing change so a stale clear timer does nothing.
    typing_generation: u64,
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
    /// Pictures by photo_for id: a file URL, or None for "has none".
    photos: HashMap<String, Option<String>>,
    /// Picture downloads in flight.
    photo_fetching: HashSet<String>,
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

/// Ask the desktop what to share (its picker), then offer it to the call.
/// Sending starts when Teams answers ([`reoffer_reply`]).
async fn offer_screen() -> anyhow::Result<()> {
    // Only open the desktop's picker when the call can take a screen.
    {
        let mut slot = call_slot().lock().await;
        let call = MediaCall::of(&mut slot).context("The call has ended")?;
        anyhow::ensure!(call.can_share(), "This call can't take a shared screen");
    }
    let (capture, frames) = teams_cli::calling::screencast::ScreenCapture::start().await?;
    let mut guard = call_slot().lock().await;
    let slot = &mut *guard;
    MediaCall::of(slot)
        .context("The call has ended")?
        .offer_media(Reoffer::Share(true))
        .await?;
    slot.share_pending = Some((capture, frames));
    Ok(())
}

/// Stop sending our screen and tell the call.
async fn stop_screen() -> anyhow::Result<()> {
    let mut guard = call_slot().lock().await;
    let slot = &mut *guard;
    slot.share_pending = None;
    let mut call = MediaCall::of(slot).context("The call has ended")?;
    call.stop_share();
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

fn call_slot() -> &'static tokio::sync::Mutex<CallSlot> {
    static SLOT: OnceLock<tokio::sync::Mutex<CallSlot>> = OnceLock::new();
    SLOT.get_or_init(Default::default)
}

/// Log media health every 5 s while a call lasts.
fn spawn_call_stats_logger() {
    runtime().spawn(async {
        loop {
            tokio::time::sleep(std::time::Duration::from_secs(5)).await;
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
                        "call audio"
                    );
                }
            } else {
                return;
            }
        }
    });
}

/// How many calls the Calls history shows.
const CALL_HISTORY_LIMIT: usize = 100;

/// Where downloads go: $XDG_DOWNLOAD_DIR, else ~/Downloads.
fn download_dir() -> Option<std::path::PathBuf> {
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
/// messages unless you asked for mentions only; channel posts only when
/// they mention you.
fn should_notify(
    mine: bool,
    open: bool,
    empty: bool,
    banners_on: bool,
    mentions_only: bool,
    channel: bool,
    mentioned: bool,
) -> bool {
    if mine || open || empty || !banners_on {
        return false;
    }
    mentioned || !(channel || mentions_only)
}

/// Longest message text shown in a notification.
const NOTIFICATION_BODY_CHARS: usize = 200;

/// A typing indicator disappears this long after the last typing event.
const TYPING_TTL_SECS: u64 = 6;
/// Send our own typing indicator at most this often.
const TYPING_SEND_INTERVAL_SECS: u64 = 3;

/// How long an unanswered call rings before it counts as missed.
const RING_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(60);

/// How many chats and messages to load per request.
const CHAT_LIMIT: usize = 50;
const MESSAGE_LIMIT: usize = 50;

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
    let mut list: Vec<serde_json::Value> = vec![json!({
        "id": "48:notes",
        "name": format!("{} (You)", me.display_name),
        "isGroup": false,
        "isSelf": true,
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

async fn load_messages(chat_id: String) -> anyhow::Result<(String, Option<(String, String)>)> {
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
    let mut timeline = api::messages::read_timeline(&client, &chat_id, MESSAGE_LIMIT).await?;
    api::messages::mark_first_unread(&mut timeline, opened_at);
    {
        let here = deleted_here().lock().unwrap();
        timeline.retain(|m| !m.deleted || here.contains(&m.id));
    }
    match api::messages::peer_read_horizon(&client, &chat_id).await {
        Ok(h) => api::messages::apply_seen(&mut timeline, h),
        Err(e) => tracing::debug!("read horizons unavailable: {}", short_error(&e)),
    }
    for img in timeline.iter_mut().flat_map(|m| m.images.iter_mut()) {
        match cached_image(&client, img).await {
            Ok(path) => img.local_path = format!("file://{}", path.display()),
            Err(e) => tracing::warn!("image download failed: {}", short_error(&e)),
        }
    }
    let last_id = timeline
        .iter()
        .rev()
        .find(|m| m.kind == "message")
        .map(|m| (m.id.clone(), m.client_message_id.clone()));
    Ok((serde_json::to_string(&timeline)?, last_id))
}

/// A call event arrived: ring for a new invitation; anything else about
/// the current call is logged by shape (never by content) so call-end
/// signalling can be recognised.
async fn on_call_event(qt: &cxx_qt::CxxQtThread<qobject::Backend>, json: &str) {
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

/// The owner and object id behind a photo_for id.
fn photo_target(id: &str, my_oid: Option<&str>) -> Option<(api::directory::PhotoOwner, String)> {
    use api::directory::PhotoOwner;
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
    fn start_push(self: Pin<&mut Self>) {
        static STARTED: AtomicBool = AtomicBool::new(false);
        if STARTED.swap(true, Ordering::SeqCst) {
            return;
        }
        let mut events = teams_cli::event_hub::subscribe();
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
                if ev.kind == EventKind::Call {
                    on_call_event(&qt, &ev.json).await;
                    continue;
                }
                for m in teams_cli::event_hub::message_events(&ev.json) {
                    let qt2 = qt.clone();
                    let _ = qt.queue(move |mut this| this.as_mut().maybe_notify(m, qt2));
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
                    spawn_call_stats_logger();
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

    pub fn start_call(mut self: Pin<&mut Self>) {
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
        if outgoing::is_group_chat(&chat_id) {
            self.start_group_call(chat_id, peer);
            return;
        }
        let Some(callee) = outgoing::callee_mri_for_chat(&chat_id, &my_oid) else {
            self.as_mut()
                .set_status_text(QString::from("Calls are available in 1:1 chats"));
            return;
        };
        self.as_mut().set_call_peer(peer);
        self.as_mut()
            .set_call_peer_id(QString::from(callee.as_str()));
        self.as_mut().set_call_video_offered(false);
        self.as_mut().set_call_meeting(false);
        self.as_mut().set_call_muted(false);
        self.as_mut().set_call_state(QString::from("calling"));
        let qt = self.qt_thread();
        let (cancel_tx, cancel_rx) = tokio::sync::oneshot::channel();
        runtime().block_on(async { call_slot().lock().await.cancel_placing = Some(cancel_tx) });
        runtime().spawn(async move {
            let result = outgoing::place_call(&chat_id, &callee, cancel_rx).await;
            let mut slot = call_slot().lock().await;
            slot.cancel_placing = None;
            match result {
                Ok(call) => {
                    let has_audio = call.has_audio();
                    let can_dtmf = call.can_dtmf();
                    let can_video = call.can_send_video();
                    let can_share = call.can_share();
                    tracing::info!(
                        has_audio,
                        can_dtmf,
                        can_video,
                        can_share,
                        "outgoing call connected"
                    );
                    slot.outgoing = Some(call);
                    drop(slot);
                    spawn_call_stats_logger();
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
                    tracing::info!("outgoing call ended: {msg}");
                    let _ = qt.queue(move |mut this| {
                        this.as_mut().set_status_text(QString::from(msg.as_str()));
                        this.as_mut().end_call_ui();
                    });
                }
            }
        });
    }

    /// A group call in a group chat, shown with the meeting window.
    fn start_group_call(mut self: Pin<&mut Self>, chat_id: String, title: QString) {
        self.as_mut().set_call_peer(title);
        self.as_mut().set_call_peer_id(QString::default());
        self.as_mut().rust_mut().roster.clear();
        self.as_mut().set_call_roster_json(QString::from("[]"));
        self.as_mut()
            .set_call_thread_id(QString::from(chat_id.as_str()));
        self.as_mut().set_call_meeting(true);
        self.as_mut().set_call_video_offered(false);
        self.as_mut().set_call_muted(false);
        self.as_mut().set_call_state(QString::from("connecting"));
        let qt = self.qt_thread();
        let (cancel_tx, cancel_rx) = tokio::sync::oneshot::channel();
        runtime().block_on(async { call_slot().lock().await.cancel_placing = Some(cancel_tx) });
        runtime().spawn(async move {
            let result = outgoing::start_group_call(&chat_id, cancel_rx).await;
            let mut slot = call_slot().lock().await;
            slot.cancel_placing = None;
            match result {
                Ok(call) => {
                    let has_audio = call.has_audio();
                    let can_dtmf = call.can_dtmf();
                    tracing::info!(has_audio, can_dtmf, "group call started");
                    slot.outgoing = Some(call);
                    drop(slot);
                    spawn_call_stats_logger();
                    let _ = qt.queue(move |mut this| {
                        this.as_mut().set_call_has_audio(has_audio);
                        this.as_mut().set_call_can_dtmf(can_dtmf);
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
        let title = if title.is_empty() {
            QString::from("Meeting")
        } else {
            title.clone()
        };
        self.as_mut().set_call_peer(title);
        self.as_mut().set_call_peer_id(QString::default());
        self.as_mut().rust_mut().roster.clear();
        self.as_mut().set_call_roster_json(QString::from("[]"));
        self.as_mut()
            .set_call_thread_id(QString::from(link.thread_id.as_str()));
        self.as_mut().set_call_options_url(QString::from(
            link.options_url().unwrap_or_default().as_str(),
        ));
        self.as_mut()
            .set_call_chat_url(QString::from(link.chat_url().as_str()));
        self.as_mut().set_call_meeting(true);
        self.as_mut().set_call_video_offered(false);
        self.as_mut().set_call_muted(false);
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
                    let has_audio = call.has_audio();
                    let can_dtmf = call.can_dtmf();
                    tracing::info!(has_audio, can_dtmf, "meeting joined");
                    // Who was here before us (updates only carry changes).
                    match call.participants().await {
                        Ok(people) => {
                            tracing::info!(count = people.len(), "meeting participants");
                            // Only people the updates haven't told us about:
                            // the list carries names, not hands or roles.
                            let _ = qt.queue(move |mut this| {
                                let known: Vec<String> =
                                    this.rust().roster.iter().map(|p| p.id.clone()).collect();
                                let missing = people
                                    .into_iter()
                                    .filter(|p| !known.contains(&p.id))
                                    .collect();
                                this.as_mut().apply_roster(missing)
                            });
                        }
                        Err(e) => tracing::info!("participants: {}", short_error(&e)),
                    }
                    slot.outgoing = Some(call);
                    drop(slot);
                    spawn_call_stats_logger();
                    let _ = qt.queue(move |mut this| {
                        this.as_mut().set_call_has_audio(has_audio);
                        this.as_mut().set_call_can_dtmf(can_dtmf);
                        this.as_mut().set_call_state(QString::from("connected"));
                    });
                }
                Err(e) => {
                    drop(slot);
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

    pub fn hang_up(mut self: Pin<&mut Self>) {
        self.as_mut().end_call_ui();
        runtime().spawn(async {
            let mut slot = call_slot().lock().await;
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
            let result = if call.can_reoffer() {
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
        self.as_mut().set_call_muted(muted);
        runtime().spawn(async move {
            let slot = call_slot().lock().await;
            if let Some(call) = slot.active.as_ref() {
                call.set_muted(muted);
            }
            if let Some(call) = slot.outgoing.as_ref() {
                call.set_muted(muted);
            }
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
                stop_screen().await
            };
            if let Err(e) = result {
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

    /// Apply roster changes and publish the roster to QML.
    fn apply_roster(mut self: Pin<&mut Self>, delta: Vec<teams_cli::calling::roster::Participant>) {
        let mut roster = std::mem::take(&mut self.as_mut().rust_mut().roster);
        teams_cli::calling::roster::apply(&mut roster, delta);
        let json = serde_json::to_string(&roster).unwrap_or_else(|_| "[]".into());
        self.as_mut().rust_mut().roster = roster;
        self.as_mut()
            .set_call_roster_json(QString::from(json.as_str()));
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
                    let mris: Vec<String> = this
                        .rust()
                        .chats
                        .iter()
                        .filter_map(|c| c["peerMri"].as_str().map(str::to_string))
                        .collect();
                    let _ = tx.send(mris);
                });
                let mris = rx.await.unwrap_or_default();
                match teams_cli::api::presence::get_presences(&http, &mris).await {
                    Ok(list) => {
                        let _ = qt.queue(move |mut this| {
                            for p in list {
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

    /// Show a desktop notification for someone else's message, unless its
    /// chat is open in the focused window.
    fn maybe_notify(
        self: Pin<&mut Self>,
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
        // Settings > Notifications and activity can turn banners off, or
        // keep only mentions.
        let settings = load_settings();
        let setting = |k: &str| settings.get(k).and_then(|v| v.as_str()).map(str::to_string);
        let banners_on = setting("notifications").as_deref() != Some("off");
        let mentions_only = setting("notify_mentions_only").as_deref() == Some("on");
        let mentioned = self
            .rust()
            .my_mri
            .as_deref()
            .is_some_and(|me| m.mentions.iter().any(|x| x.eq_ignore_ascii_case(me)));
        let channel = m.conversation_id.ends_with("@thread.tacv2");
        if !should_notify(
            mine,
            open,
            m.text.is_empty(),
            banners_on,
            mentions_only,
            channel,
            mentioned,
        ) {
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
        let text: String = m.text.chars().take(NOTIFICATION_BODY_CHARS).collect();
        // Where it was said, for channels and named chats.
        let body = if channel && !chat_name.is_empty() {
            format!("{chat_name}\n{text}")
        } else {
            text
        };
        let chat_id = m.conversation_id.clone();
        std::thread::spawn(move || {
            let shown = notify_rust::Notification::new()
                .appname("OST")
                .summary(&title)
                .body(&body)
                .icon("ost-desktop")
                .action("default", "Open")
                .hint(notify_rust::Hint::Category("im.received".into()))
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
        if t.conversation_id != self.rust().current_chat_id.to_string()
            || t.sender_name == self.rust().user_name.to_string()
        {
            return;
        }
        let generation = self.rust().typing_generation + 1;
        self.as_mut().rust_mut().typing_generation = generation;
        if t.stopped {
            self.as_mut().set_typing_text(QString::default());
            return;
        }
        // Typing events often omit the name; in a 1:1 chat it is the other
        // member, whose name is the chat's.
        let name = if t.sender_name.is_empty() {
            self.rust().current_chat_name.to_string()
        } else {
            t.sender_name.clone()
        };
        let text = format!("{name} is typing");
        self.as_mut().set_typing_text(QString::from(text.as_str()));
        // Teams clears the indicator if no new typing event comes in.
        let qt = self.qt_thread();
        runtime().spawn(async move {
            tokio::time::sleep(std::time::Duration::from_secs(TYPING_TTL_SECS)).await;
            let _ = qt.queue(move |mut this| {
                if this.rust().typing_generation == generation {
                    this.as_mut().set_typing_text(QString::default());
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

    pub fn search_people(mut self: Pin<&mut Self>, query: &QString) {
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
                api::directory::search_people(&client, &q).await
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
        self.message_action(move |client, chat| {
            Box::pin(async move { api::messages::edit_message(&client, &chat, &id, &text).await })
        });
    }

    pub fn delete_message(self: Pin<&mut Self>, message_id: &QString) {
        let id = message_id.to_string();
        deleted_here().lock().unwrap().insert(id.clone());
        self.message_action(move |client, chat| {
            Box::pin(async move { api::messages::delete_message(&client, &chat, &id).await })
        });
    }

    /// Run a message change in the open chat, then reload it.
    fn message_action<F>(self: Pin<&mut Self>, act: F)
    where
        F: FnOnce(
                TeamsClient,
                String,
            ) -> std::pin::Pin<
                Box<dyn std::future::Future<Output = anyhow::Result<()>> + Send>,
            > + Send
            + 'static,
    {
        let chat_id = self.rust().current_chat_id.to_string();
        if chat_id.is_empty() {
            return;
        }
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = match TeamsClient::new().await {
                Ok(client) => act(client, chat_id).await,
                Err(e) => Err(e),
            };
            let _ = qt.queue(move |mut this| match result {
                Ok(()) => this.as_mut().reload_messages(),
                Err(e) => this
                    .as_mut()
                    .set_status_text(QString::from(short_error(&e).as_str())),
            });
        });
    }

    pub fn toggle_reaction(self: Pin<&mut Self>, message_id: &QString, key: &QString, on: bool) {
        let chat_id = self.rust().current_chat_id.to_string();
        let (message_id, key) = (message_id.to_string(), key.to_string());
        if chat_id.is_empty() || message_id.is_empty() {
            return;
        }
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                api::messages::set_reaction(&client, &chat_id, &message_id, &key, on).await
            }
            .await;
            let _ = qt.queue(move |mut this| match result {
                Ok(()) => this.as_mut().reload_messages(),
                Err(e) => this
                    .as_mut()
                    .set_status_text(QString::from(short_error(&e).as_str())),
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
        let current = self.rust().current_chat_id.to_string();
        let mut list_changed = false;
        // New notifications: refresh Activity (and its badge).
        if ids.iter().any(|i| i == "48:notifications") {
            self.as_mut().load_activity();
        }
        for id in ids.into_iter().filter(|i| !i.starts_with("48:")) {
            if id == current {
                self.as_mut().set_typing_text(QString::default());
                self.as_mut().reload_messages();
            } else {
                list_changed |= self.as_mut().rust_mut().unread.insert(id);
            }
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
                        this.as_mut().load_activity();
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
        self.as_mut().set_typing_text(QString::default());
        self.as_mut().rust_mut().newest_message_id = None;
        read_at_open().lock().unwrap().remove(&chat_id.to_string());
        self.as_mut().set_current_chat_id(chat_id.clone());
        self.as_mut().set_current_chat_name(chat_name.clone());
        self.as_mut().set_messages_json(QString::from("[]"));
        self.as_mut().reload_messages();
    }

    pub fn send_message(mut self: Pin<&mut Self>, text: &QString) {
        let body = text.to_string();
        let chat_id = self.rust().current_chat_id.to_string();
        if body.trim().is_empty() || chat_id.is_empty() {
            return;
        }
        self.as_mut().set_busy(true);
        let qt = self.qt_thread();
        let sent_chat = chat_id.clone();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                api::send_message_with_client(&client, &chat_id, &body).await
            }
            .await;
            let _ = qt.queue(move |mut this| {
                this.as_mut().set_busy(false);
                match result {
                    Ok(()) => {
                        // Sent: the draft for this chat is done.
                        this.as_mut()
                            .set_draft(&QString::from(sent_chat.as_str()), &QString::default());
                        this.as_mut().reload_messages()
                    }
                    Err(e) => this
                        .as_mut()
                        .set_status_text(QString::from(short_error(&e).as_str())),
                }
            });
        });
    }

    pub fn send_reply(mut self: Pin<&mut Self>, root_id: &QString, text: &QString) {
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
        self.as_mut().set_busy(true);
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                let thread = format!("{channel};messageid={root}");
                api::send_message_with_client(&client, &thread, &body).await
            }
            .await;
            let _ = qt.queue(move |mut this| {
                this.as_mut().set_busy(false);
                match result {
                    Ok(()) => this.as_mut().reload_messages(),
                    Err(e) => this
                        .as_mut()
                        .set_status_text(QString::from(short_error(&e).as_str())),
                }
            });
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
                    Ok((json, last_id)) => {
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
                api::list_teams_data(&client).await
            }
            .await;
            match result {
                Ok(teams) => {
                    let list: Vec<_> = teams
                        .iter()
                        .map(|t| {
                            json!({
                                "id": t.id,
                                "name": t.name,
                                "channels": t.channels.iter().map(|c| json!({"id": c.id, "name": c.name})).collect::<Vec<_>>(),
                            })
                        })
                        .collect();
                    let text = serde_json::to_string(&list).unwrap_or_else(|_| "[]".into());
                    let _ = qt.queue(move |mut this| this.as_mut().set_teams_json(QString::from(text.as_str())));
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
            if owner == api::directory::PhotoOwner::Team {
                "team"
            } else {
                "user"
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
            let result = async { api::store::apps(&TeamsClient::new().await?).await }.await;
            let _ = qt.queue(move |mut this| {
                this.as_mut().set_store_busy(false);
                let text = match result {
                    Ok(apps) => json!({ "apps": apps }).to_string(),
                    Err(e) => json!({ "error": short_error(&e) }).to_string(),
                };
                this.as_mut().set_store_json(QString::from(text.as_str()));
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
            menu: Vec::new(),
            context_menu: Vec::new(),
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
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                match op.as_str() {
                    "rename" => api::tabs::rename(&client, &channel, &tab, &arg).await,
                    "remove" => api::tabs::remove(&client, &channel, &tab).await,
                    "left" | "right" => {
                        api::tabs::move_tab(&client, &channel, &tab, op == "right").await
                    }
                    _ => Err(anyhow::anyhow!("Unknown tab change")),
                }
            }
            .await;
            let _ = qt.queue(move |mut this| {
                if let Err(e) = &result {
                    tracing::warn!("tab {op} failed: {e:#}");
                }
                let outcome = json!({ "op": op, "tab": tab, "ok": result.is_ok() }).to_string();
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

    pub fn set_my_status(mut self: Pin<&mut Self>, status: &QString) {
        let status = status.to_string();
        let forced = (status != "Reset").then(|| status.clone());
        // Show it at once; the presence service confirms on the next poll.
        if let (Some(f), Some(me)) = (forced.clone(), self.rust().my_mri.clone()) {
            self.as_mut().rust_mut().presence.insert(me, f);
            self.as_mut().publish_chats();
        }
        runtime().spawn(async move {
            let http = reqwest::Client::new();
            if let Err(e) =
                teams_cli::api::presence::force_availability(&http, forced.as_deref()).await
            {
                tracing::warn!("set status failed: {}", short_error(&e));
            }
        });
    }

    pub fn audio_devices(self: Pin<&mut Self>) -> QString {
        let (inputs, outputs) = teams_cli::calling::audio::list_devices();
        QString::from(
            json!({ "inputs": inputs, "outputs": outputs })
                .to_string()
                .as_str(),
        )
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

    pub fn send_files(mut self: Pin<&mut Self>, paths: &QString, text: &QString) {
        let chat_id = self.rust().current_chat_id.to_string();
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
                api::files::send_with_files(&client, &chat_id, &text, files).await
            }
            .await;
            let _ = qt.queue(move |mut this| {
                this.as_mut().set_busy(false);
                match result {
                    Ok(()) => {
                        this.as_mut().set_status_text(QString::default());
                        this.as_mut().reload_messages();
                    }
                    Err(e) => this
                        .as_mut()
                        .set_status_text(QString::from(short_error(&e).as_str())),
                }
            });
        });
    }

    pub fn send_rich(mut self: Pin<&mut Self>, editor_html: &QString) {
        let html = editor_html.to_string();
        let chat_id = self.rust().current_chat_id.to_string();
        if chat_id.is_empty() || html.trim().is_empty() {
            return;
        }
        self.as_mut().set_busy(true);
        let qt = self.qt_thread();
        let sent_chat = chat_id.clone();
        runtime().spawn(async move {
            let result = async {
                let client = TeamsClient::new().await?;
                api::send_html_with_client(&client, &chat_id, &html).await
            }
            .await;
            let _ = qt.queue(move |mut this| {
                this.as_mut().set_busy(false);
                match result {
                    Ok(()) => {
                        this.as_mut()
                            .set_draft(&QString::from(sent_chat.as_str()), &QString::default());
                        this.as_mut().reload_messages()
                    }
                    Err(e) => this
                        .as_mut()
                        .set_status_text(QString::from(short_error(&e).as_str())),
                }
            });
        });
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
mod tests {
    use super::{photo_target, should_notify};
    use teams_cli::api::directory::PhotoOwner;

    const OID: &str = "4287e791-1b98-4963-8b94-281c50472683";

    #[test]
    fn notifications_follow_teams_defaults() {
        // (mine, open, empty, banners, mentions_only, channel, mentioned)
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
        // Anything that could change the request path is refused.
        assert_eq!(photo_target("../../me", None), None);
        assert_eq!(photo_target("8:orgid:abc?x=1", None), None);
        assert_eq!(photo_target(&format!("{OID}/x"), None), None);
    }
}

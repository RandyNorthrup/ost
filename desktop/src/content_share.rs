//! Presenting content-sharing sessions as Teams (TASK-0214;
//! docs/spec/content-sharing.md): Microsoft Whiteboard, PowerPoint Live,
//! Excel Live and Annotate. The call window shows them from
//! `call_content_json`:
//!
//! `{mine: Session|null, others: [Session], starting: kind|"", error}`,
//! a Session being content_sharing::Session (`correlationId, presenter,
//! presenterName, content, state, sequence, mine`).

use super::*;
use teams_cli::calling::content_sharing as cs;

/// What the call window shows of content sharing.
#[derive(Default)]
pub struct ContentShare {
    pub mine: Option<cs::Session>,
    /// Sessions others present, in the order they started.
    pub others: Vec<cs::Session>,
    /// The kind being started ("whiteboard", "ppt", "excel",
    /// "annotation"), until the session starts or fails.
    pub starting: String,
    pub error: String,
    /// The board our frame shows while we present Whiteboard or Annotate
    /// (the session's own address; Annotate's comes from the meeting).
    pub board: String,
    /// The tray's recent decks and workbooks: {ppt: [...], excel: [...]}.
    pub recent: serde_json::Value,
    /// Who took our presentation over (Teams' PptSharingStolen alert),
    /// until it's dismissed or we take it back.
    pub taken_by: String,
}

impl qobject::Backend {
    pub(crate) fn show_content(mut self: Pin<&mut Self>) {
        let c = &self.rust().content;
        let json = serde_json::json!({
            "mine": c.mine,
            "others": c.others,
            "starting": c.starting,
            "error": c.error,
            "board": c.board,
            "recent": c.recent,
            "takenBy": c.taken_by,
        })
        .to_string();
        if self.rust().call_content_json.to_string() != json {
            self.as_mut().set_call_content_json(QString::from(json.as_str()));
        }
    }

    /// Start presenting `kind` ("whiteboard", "annotation"; `args` JSON
    /// for the others): Teams' startWhiteboardSharing / startAnnotation /
    /// startFileSharing. The board's address is found first (the
    /// meeting's own board, as Teams' getMeetingWhiteboard), then the
    /// session is added to the conversation.
    pub fn content_share_start(mut self: Pin<&mut Self>, kind: &QString, args: &QString) {
        let kind = kind.to_string();
        let args: serde_json::Value = serde_json::from_str(&args.to_string()).unwrap_or_default();
        if !self.rust().content.starting.is_empty() || self.rust().content.mine.is_some() {
            return;
        }
        self.as_mut().rust_mut().content.starting = kind.clone();
        self.as_mut().rust_mut().content.error.clear();
        self.as_mut().show_content();
        let title = self.rust().call_peer.to_string();
        let me_oid = self.rust().user_mri.to_string().trim_start_matches("8:orgid:").to_string();
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let r = start_content(&kind, &args, &title, &me_oid).await;
            let _ = qt.queue(move |mut this| {
                this.as_mut().rust_mut().content.starting.clear();
                match r {
                    Ok((s, board)) => {
                        tracing::info!(kind = s.kind(), "presenting content");
                        this.as_mut().rust_mut().content.mine = Some(s);
                        this.as_mut().rust_mut().content.board = board;
                    }
                    Err(e) => {
                        tracing::warn!("presenting {kind}: {}", short_error(&e));
                        this.as_mut().rust_mut().content.error = short_error(&e);
                    }
                }
                this.as_mut().show_content();
            });
        });
    }

    /// The session we present changed its state (Whiteboard reported its
    /// board, a slide moved): Teams' updateContentSharingSessionState.
    pub fn content_share_state(self: Pin<&mut Self>, state: &QString) {
        let state = state.to_string();
        let qt = self.qt_thread();
        runtime().spawn(async move {
            // The session's links come with addModalitySuccess, which can
            // follow the page's first report: wait for them (Teams' 65 s).
            let mut slot = call_slot().lock().await;
            for _ in 0..130 {
                let ready = slot.outgoing.as_ref().and_then(|c| c.my_content()).is_some_and(|m| m.links.update_state.is_some());
                let gone = slot.outgoing.as_ref().and_then(|c| c.my_content()).is_none();
                if ready || gone {
                    break;
                }
                drop(slot);
                tokio::time::sleep(std::time::Duration::from_millis(500)).await;
                slot = call_slot().lock().await;
            }
            let Some(call) = slot.outgoing.as_mut() else { return };
            if let Err(e) = call.update_content_state(&state).await {
                tracing::warn!("content state: {}", short_error(&e));
                return;
            }
            let mine = call.my_content().cloned();
            drop(slot);
            let _ = qt.queue(move |mut this| {
                this.as_mut().rust_mut().content.mine = mine;
                this.as_mut().show_content();
            });
        });
    }

    /// Stop presenting (Teams' Stop sharing / Stop presenting).
    pub fn content_share_stop(mut self: Pin<&mut Self>) {
        self.as_mut().rust_mut().content.mine = None;
        self.as_mut().rust_mut().content.board.clear();
        self.as_mut().show_content();
        runtime().spawn(async move {
            if let Some(call) = call_slot().lock().await.outgoing.as_mut()
                && let Err(e) = call.stop_content_sharing().await
            {
                tracing::warn!("stopping the content share: {}", short_error(&e));
            }
        });
    }

    /// Take over a PowerPoint Live session someone else presents (Teams'
    /// Take control): once the service answers it is ours, and the stage
    /// switches PowerPoint to the presenter's role.
    pub fn content_take_control(self: Pin<&mut Self>, correlation: &QString) {
        let corr = correlation.to_string();
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let r = {
                let mut slot = call_slot().lock().await;
                match slot.outgoing.as_mut() {
                    Some(call) => call.take_content_control(&corr).await,
                    None => Err(anyhow::anyhow!("Not in a meeting")),
                }
            };
            let _ = qt.queue(move |mut this| {
                match r {
                    Ok(s) => {
                        let c = &mut this.as_mut().rust_mut().content;
                        c.others.retain(|o| o.correlation_id != s.correlation_id);
                        c.taken_by.clear();
                        c.mine = Some(s);
                    }
                    Err(e) => {
                        tracing::warn!("taking control of the presentation: {}", short_error(&e));
                        this.as_mut().rust_mut().content.error = short_error(&e);
                    }
                }
                this.as_mut().show_content();
            });
        });
    }

    /// PowerPoint Live's Layout ▸ Cameo (on) or Content only (off): Teams
    /// publishes the presenter's weatherPerson state with mode "Cameo" (the
    /// default presenter position, zOrder 2) so attendees switch their
    /// slide shows too; Content only takes it back.
    pub fn content_ppt_cameo(self: Pin<&mut Self>, on: bool) {
        runtime().spawn(async move {
            let s = teams_cli::calling::presenter_mode::config::WP_PRESENTER_SIZE;
            let layout = on.then(|| serde_json::json!({ "mode": "Cameo", "x": 1.0 - s, "y": 1.0 - s, "width": s, "height": s, "zOrder": 2 }));
            let mut slot = call_slot().lock().await;
            let Some(call) = slot.outgoing.as_mut() else { return };
            match call.weather_person(layout).await {
                Ok(()) => tracing::info!(on, "PowerPoint Live layout published"),
                Err(e) => tracing::warn!("PowerPoint Live layout: {}", short_error(&e)),
            }
        });
    }

    pub fn cameo_socket(&self) -> QString {
        QString::from(crate::cameo_feed::socket().as_str())
    }

    /// PowerPoint Live's pointer to everyone (LiveInking).
    pub fn content_send_inking(self: Pin<&mut Self>, event_data: &QString) {
        let data = event_data.to_string();
        runtime().spawn(async move {
            let sender = call_slot().lock().await.outgoing.as_ref().and_then(|c| c.live_inking_sender());
            if let Some(s) = sender
                && let Err(e) = s.send(&data).await
            {
                tracing::debug!("LiveInking: {}", short_error(&e));
            }
        });
    }

    /// A shared board's frame address (Teams' whiteboard renderer): the
    /// session's address with Teams' parameters.
    pub fn content_board_frame_url(&self, session_url: &QString, initiator: bool, extra: &QString) -> QString {
        let (call_id, thread) = runtime().block_on(async {
            let slot = call_slot().lock().await;
            slot.outgoing.as_ref().map(|c| (c.call_id().to_string(), c.thread().to_string())).unwrap_or_default()
        });
        let extra: serde_json::Value = serde_json::from_str(&extra.to_string()).unwrap_or_default();
        let pairs: Vec<(String, String)> = extra
            .as_object()
            .into_iter()
            .flatten()
            .map(|(k, v)| (k.clone(), v.as_str().map(str::to_string).unwrap_or_else(|| v.to_string())))
            .collect();
        let pairs: Vec<(&str, String)> = pairs.iter().map(|(k, v)| (k.as_str(), v.clone())).collect();
        let meeting_id = cs::meeting_id(&thread);
        let user = self.rust().user_mri.to_string().trim_start_matches("8:orgid:").to_string();
        let url = api::app_host::shared_board_frame_url(
            &session_url.to_string(),
            &uuid::Uuid::new_v4().to_string(),
            initiator,
            &meeting_id,
            &call_id,
            &user,
            &self.tenant_id().to_string(),
            &pairs,
        );
        QString::from(url.unwrap_or_default().as_str())
    }

    /// Keep the board Whiteboard reported (`changeWhiteboardUrl`) for the
    /// meeting, as Teams does: v2/whiteboard for Whiteboard, annotation for
    /// Annotate.
    pub fn content_save_board(self: Pin<&mut Self>, kind: &QString, url: &QString) {
        let (kind, url) = (kind.to_string(), url.to_string());
        let me_oid = self.rust().user_mri.to_string().trim_start_matches("8:orgid:").to_string();
        runtime().spawn(async move {
            let (thread, organizer) = {
                let slot = call_slot().lock().await;
                let Some(c) = slot.outgoing.as_ref() else { return };
                (c.thread().to_string(), c.organizer_oid().unwrap_or(&me_oid).to_string())
            };
            let r = async {
                let client = TeamsClient::new().await?;
                if kind == "annotation" {
                    api::app_host::save_meeting_annotation_board(&client, &thread, &organizer, &url).await
                } else {
                    api::app_host::save_meeting_board(&client, &thread, &organizer, &url).await
                }
            }
            .await;
            match r {
                Ok(()) => tracing::info!(%kind, "kept the meeting's board"),
                Err(e) => tracing::warn!("keeping the meeting's {kind} board: {}", short_error(&e)),
            }
        });
    }

    /// What PowerPoint Live's host (ppt_host.js) posts and says: the slide
    /// show form (Teams' populateFormData fields, in its order) and the
    /// Initialize message's file, for the session's deck (`session`), as
    /// the presenter or an attendee.
    pub fn content_ppt_config(&self, session: &QString, presenter_name: &QString, attendees: i32, dark: bool) -> QString {
        let s: serde_json::Value = serde_json::from_str(&session.to_string()).unwrap_or_default();
        let c = s.get("content").cloned().unwrap_or_default();
        let st = |v: &serde_json::Value, k: &str| v.get(k).and_then(|x| x.as_str()).unwrap_or_default().to_string();
        let mine = s.get("mine").and_then(|m| m.as_bool()).unwrap_or(false);
        let state: serde_json::Value = serde_json::from_str(&st(&s, "state")).unwrap_or_default();
        let start = state.get("slideIndex").and_then(|i| i.as_i64()).map_or(1, |i| i + 1);
        let mappings = state.get("timeLineMappings").cloned().unwrap_or_else(|| serde_json::json!([]));
        let (call_id, participant, endpoint, thread) = runtime().block_on(async {
            let slot = call_slot().lock().await;
            slot.outgoing
                .as_ref()
                .map(|c| (c.call_id().to_string(), c.participant_id().to_string(), c.endpoint_id().unwrap_or_default().to_string(), c.thread().to_string()))
                .unwrap_or_default()
        });
        let wac = st(&c, "wacUrl");
        let (pods_region, wac_region) = api::live_share::wac_region(&wac).unwrap_or_else(|| ("usc".into(), "usc".into()));
        let pods = format!("https://{pods_region}.pods.officeapps.live.com/");
        // The presenter's viewer is the deck's correlation id; an
        // attendee's a new one.
        let host_session = if mine { st(&c, "correlationId") } else { uuid::Uuid::new_v4().to_string() };
        let user = self.rust().user_mri.to_string().trim_start_matches("8:orgid:").to_string();
        let e = |v: &str| teams_cli::api::tabs::encode_uri_component(v);
        let now = chrono::Utc::now().timestamp_millis().to_string();
        let name = st(&c, "name");
        let fields: Vec<(&str, String)> = vec![
            ("parentWindowOrigin", "https://teams.microsoft.com".into()),
            ("fileurl", st(&c, "fileGetUrl")),
            ("fileName", e(&name)),
            ("fileSize", c.get("fileSize").map(|v| v.to_string()).unwrap_or_default()),
            ("presentationUrl", st(&c, "snapPresentationUrl")),
            ("DocID", e(&st(&c, "id"))),
            ("docId", e(&st(&c, "id"))),
            ("ETag", st(&c, "etag")),
            ("hostsessionid", host_session.clone()),
            ("X-UserSessionId", host_session.clone()),
            ("ApiId", host_session.clone()),
            ("isRtl", "false".into()),
            ("hostExperience", "react-web-client".into()),
            ("environment", "prod".into()),
            ("region", "amer".into()),
            ("teamsbuildversion", "49/26110100716".into()),
            ("user_id", e(&user)),
            ("tid", e(&self.tenant_id().to_string())),
            ("contentId", e(&st(&s, "sessionId"))),
            ("meetingChatId", e(&thread)),
            ("endpointId", e(&endpoint)),
            ("uihRing", e("general")),
            ("isHighContrast", "false".into()),
            ("highContrastColorSettings", String::new()),
            ("useZipItSnap", "false".into()),
            ("isTest", "false".into()),
            ("sessionSource", st(&c, "source")),
            ("isSlideCaptureSupported", "true".into()),
            ("wdPresenterViewInTeams", "true".into()),
            ("enablePptSharingWebviewContainer", "false".into()),
            ("enableMovePrivateViewingToPPT", "true".into()),
            ("enableMovePresenterNameToPPT", "true".into()),
            ("enableMagnifySync", "true".into()),
            ("enableInkToExplainFeature", "true".into()),
            ("enablePptLiveConfigurableLayouts", "false".into()),
            ("enableSSToolbarNavControlsForPresenter", "true".into()),
            ("enableSSToolbarNavControlsForAttendee", "true".into()),
            ("enableSSToolbarTogglePrivateViewingControl", "true".into()),
            ("enableRefreshPptSharingSession", "true".into()),
            ("enableScreenShareFallback", "false".into()),
            ("showScreenShareFallbackButton", "false".into()),
            ("useStreamEmbedInPreview", "false".into()),
            ("enableStreamVideoInitQueue", "false".into()),
            ("wdBrowserShapeBuilderCompatible", "true".into()),
            ("wdIsFileTypeSupportedForModernSlideShow", "true".into()),
            ("isSvg", "undefined".into()),
            ("startingslideindex", start.to_string()),
            ("startingtimelinemappings", mappings.to_string()),
            ("startFromTime", now.clone()),
            ("initWopiTime", now.clone()),
            ("bootstrapperInitTime", now.clone()),
            ("presentationUrlFlagEnabled", "false".into()),
            ("isIC3BackUpChannelEnabled", "true".into()),
            ("sliceLoadTime", now.clone()),
            ("createViewerTime", now.clone()),
            ("previewSessionLoadAppTime", now.clone()),
            ("loadSlideShowTime", now.clone()),
            ("bootstrapperScriptLoadPoint", "1js_bundled".into()),
            ("ring", "5".into()),
            ("fh", e("SharePoint Online")),
            ("uih", e("teams")),
            ("odvs", pods.clone()),
            ("odve", "podView.svc/jsonAnonymous".into()),
            ("dce", e("dummy-url")),
            ("env", "wac".into()),
            ("cdnMA", "1".into()),
            ("presentFDUrl", format!("https://{pods_region}.present.officeapps.live.com/")),
            ("wdslideindex", start.to_string()),
            ("utb", "true".into()),
            ("wdeaa", "0".into()),
            ("eac", "true".into()),
            ("ekn", "true".into()),
            ("vm", "0".into()),
            ("co", "anonymous".into()),
            ("lcid", "1033".into()),
            ("ua", "true".into()),
            ("asb", "false".into()),
            ("iscombinerequest", "true".into()),
            ("wdoverrides", "useshapebuilderviewing:true,rendergifslideshow:true,videothrutransparentcanvas:true".into()),
            ("powerpointview", "ChromelessView".into()),
            ("rs", "en-us".into()),
            ("ui", "en-us".into()),
            ("hsi", host_session.clone()),
            ("hostname", e("MSTeams")),
            ("ispresenter", mine.to_string()),
            ("callid", e(&call_id)),
            ("participantid", e(&participant)),
            ("totalparticipants", attendees.max(1).to_string()),
            ("apistarttime", now.clone()),
            ("preloadapp", "false".into()),
        ];
        let cfg = serde_json::json!({
            "hostSessionId": host_session,
            "pods": pods,
            "fields": fields,
            "presenter": mine,
            "startSlide": start,
            "fileUrl": st(&c, "fileGetUrl"),
            "fileName": name,
            "fileSize": c.get("fileSize").cloned().unwrap_or_default(),
            "snapUrl": st(&c, "snapPresentationUrl"),
            "wacRegion": format!("https://{wac_region}-powerpoint.officeapps.live.com"),
            "presenterName": presenter_name.to_string(),
            "attendees": attendees.max(1),
            "theme": if dark { "dark" } else { "light" },
            "participantId": participant,
        });
        QString::from(cfg.to_string().as_str())
    }

    pub fn ppt_host_script(&self) -> QString {
        QString::from(include_str!("ppt_host.js"))
    }

    pub fn ppt_cameo_stream_script(&self) -> QString {
        QString::from(include_str!("ppt_cameo_stream.js"))
    }

    /// Load the share tray's recent decks and workbooks (Office's MRU).
    pub fn content_recent_load(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let Ok(client) = TeamsClient::new().await else { return };
            let ppt = api::live_share::recent_docs(&client, false).await.unwrap_or_else(|e| {
                tracing::warn!("recent decks: {}", short_error(&e));
                Vec::new()
            });
            let excel = api::live_share::recent_docs(&client, true).await.unwrap_or_default();
            tracing::info!(decks = ppt.len(), workbooks = excel.len(), "share tray recent files");
            let _ = qt.queue(move |mut this| {
                this.as_mut().rust_mut().content.recent = serde_json::json!({ "ppt": ppt, "excel": excel });
                this.as_mut().show_content();
            });
        });
    }

    /// The call ended: nothing is presented any more.
    pub(crate) fn content_reset(mut self: Pin<&mut Self>) {
        let recent = std::mem::take(&mut self.as_mut().rust_mut().content.recent);
        self.as_mut().rust_mut().content = ContentShare { recent, ..Default::default() };
        self.as_mut().show_content();
    }

    /// The roster changed: the sessions others present (Teams'
    /// handleIncomingContentSharingFromRoster). New ones are joined, to
    /// get their state updates; ended ones go.
    pub(crate) fn content_from_roster(mut self: Pin<&mut Self>) {
        // Your other devices' sessions too (Teams presenting on another
        // device): only the one this device presents is left out.
        let mine = self.rust().content.mine.as_ref().map(|m| m.correlation_id.clone()).unwrap_or_default();
        let me = self.rust().user_mri.to_string().to_ascii_lowercase();
        let starting = !self.rust().content.starting.is_empty();
        let now: Vec<cs::Session> = self
            .rust()
            .roster
            .iter()
            .filter(|p| p.active)
            .flat_map(|p| p.content_sessions.iter().filter_map(|i| cs::session_from_roster(i, &p.id, &p.name)))
            .filter(|s| !s.correlation_id.is_empty() && s.correlation_id != mine)
            // Ours while it starts (before the conversation names it).
            .filter(|s| !(starting && s.presenter == me))
            .collect();
        let before = std::mem::take(&mut self.as_mut().rust_mut().content.others);
        let mut others = Vec::new();
        let mut fresh = Vec::new();
        for s in now {
            match before.iter().find(|b| b.correlation_id == s.correlation_id) {
                // Known: keep the newest state we have.
                Some(b) => {
                    let mut k = b.clone();
                    if b.sequence == 0 && !s.state.is_empty() {
                        k.state = s.state.clone();
                    }
                    others.push(k)
                }
                None => {
                    tracing::info!(kind = s.kind(), presenter = %s.presenter, content = %if s.kind() == "annotation" { s.content.to_string() } else { String::new() }, state = %if s.kind() == "annotation" { s.state.clone() } else { String::new() }, "someone presents content");
                    fresh.push(s.clone());
                    others.push(s);
                }
            }
        }
        let gone: Vec<String> = before
            .iter()
            .filter(|b| !others.iter().any(|o| o.correlation_id == b.correlation_id))
            .map(|b| b.correlation_id.clone())
            .collect();
        self.as_mut().rust_mut().content.others = others;
        self.as_mut().show_content();
        if fresh.is_empty() && gone.is_empty() {
            return;
        }
        let qt = self.qt_thread();
        runtime().spawn(async move {
            let mut slot = call_slot().lock().await;
            // A meeting we joined, or one we were invited into and
            // answered (a Teams Rooms device).
            let slot = &mut *slot;
            if slot.outgoing.is_none() {
                let Some(call) = slot.active.as_mut() else {
                    // Not answered yet (a room's invitation: the roster can
                    // come before the answer): seen again as new next time,
                    // so it's joined then.
                    let ids: Vec<String> = fresh.iter().map(|s| s.correlation_id.clone()).collect();
                    let _ = qt.queue(move |mut this| this.as_mut().rust_mut().content.others.retain(|o| !ids.contains(&o.correlation_id)));
                    return;
                };
                for g in &gone {
                    call.forget_content(g);
                }
                for s in fresh {
                    match call.join_content(s).await {
                        Ok(joined) => {
                            let _ = qt.queue(move |mut this| {
                                if let Some(o) = this.as_mut().rust_mut().content.others.iter_mut().find(|o| o.correlation_id == joined.correlation_id) {
                                    if !joined.state.is_empty() {
                                        o.state = joined.state.clone();
                                    }
                                    o.sequence = joined.sequence;
                                }
                                this.as_mut().show_content();
                            });
                        }
                        Err(e) => tracing::warn!("joining a content share: {}", short_error(&e)),
                    }
                }
                return;
            }
            let Some(call) = slot.outgoing.as_mut() else { return };
            for g in &gone {
                call.forget_content(g);
            }
            for s in fresh {
                match call.join_content(s).await {
                    Ok(joined) => {
                        let _ = qt.queue(move |mut this| {
                            if let Some(o) = this.as_mut().rust_mut().content.others.iter_mut().find(|o| o.correlation_id == joined.correlation_id) {
                                if !joined.state.is_empty() {
                                    o.state = joined.state.clone();
                                }
                                o.sequence = joined.sequence;
                            }
                            this.as_mut().show_content();
                        });
                    }
                    Err(e) => tracing::warn!("joining a content share: {}", short_error(&e)),
                }
            }
        });
    }
}

/// A call event about content sharing: our session started or failed, or
/// a state update or end for one we joined. True when it was one.
pub(crate) async fn content_event(json: &str, qt: &cxx_qt::CxxQtThread<qobject::Backend>) -> bool {
    // Someone's PowerPoint Live pointer (proxied LiveInking messages).
    if json.contains("\"LiveInking\"") && json.contains("conversation/receiveMessage") {
        let Ok(v) = serde_json::from_str::<serde_json::Value>(json) else { return false };
        let inks = cs::live_inking(&v);
        if inks.is_empty() {
            return false;
        }
        let _ = qt.queue(move |mut this| {
            for (from, _, data) in inks {
                this.as_mut().content_inking(QString::from(from.as_str()), QString::from(data.as_str()));
            }
        });
        return true;
    }
    if !(json.contains("conversation/addModality") || json.contains("conversation/contentSharing")) {
        return false;
    }
    let Ok(v) = serde_json::from_str::<serde_json::Value>(json) else { return false };
    let mut slot = call_slot().lock().await;
    // An answered call (a room invited into a meeting): the updates and
    // ends of the sessions it joined.
    if slot.outgoing.is_none()
        && let Some(call) = slot.active.as_mut()
    {
        let Some((corr, state)) = call.content_event(&v) else { return false };
        drop(slot);
        let _ = qt.queue(move |mut this| {
            let c = &mut this.as_mut().rust_mut().content;
            match state {
                Some(st) => {
                    if let Some(o) = c.others.iter_mut().find(|o| o.correlation_id == corr) {
                        o.state = st;
                        o.sequence += 1;
                    }
                }
                None => c.others.retain(|o| o.correlation_id != corr),
            }
            this.as_mut().show_content();
        });
        return true;
    }
    let Some(call) = slot.outgoing.as_mut() else { return false };
    // Someone took control of a presentation (ours, or one we view).
    if let Some((corr, presenter, taken)) = call.content_presenter(&v) {
        let _ = qt.queue(move |mut this| {
            let name = this.rust().roster.iter().find(|p| p.id.eq_ignore_ascii_case(&presenter)).map(|p| p.name.clone()).unwrap_or_default();
            let c = &mut this.as_mut().rust_mut().content;
            if taken && let Some(mut s) = c.mine.take().filter(|m| m.correlation_id == corr) {
                tracing::info!("someone took control of our presentation");
                s.mine = false;
                s.presenter = presenter.clone();
                s.presenter_name = name.clone();
                c.others.retain(|o| o.correlation_id != corr);
                c.others.push(s);
                c.taken_by = name;
            } else if let Some(o) = c.others.iter_mut().find(|o| o.correlation_id == corr) {
                o.presenter = presenter.clone();
                o.presenter_name = name;
            }
            this.as_mut().show_content();
        });
    }
    if let Some(r) = call.content_started(&v) {
        drop(slot);
        let _ = qt.queue(move |mut this| {
            match r {
                Ok(s) => this.as_mut().rust_mut().content.mine = Some(s),
                Err(why) => {
                    this.as_mut().rust_mut().content.mine = None;
                    this.as_mut().rust_mut().content.error = why;
                }
            }
            this.as_mut().show_content();
        });
        return true;
    }
    if let Some((corr, state)) = call.content_event(&v) {
        drop(slot);
        let _ = qt.queue(move |mut this| {
            let c = &mut this.as_mut().rust_mut().content;
            match state {
                Some(st) => {
                    if let Some(o) = c.others.iter_mut().find(|o| o.correlation_id == corr) {
                        o.state = st;
                        o.sequence += 1;
                    }
                }
                None => {
                    c.others.retain(|o| o.correlation_id != corr);
                    if c.mine.as_ref().is_some_and(|m| m.correlation_id == corr) {
                        c.mine = None;
                    }
                }
            }
            this.as_mut().show_content();
        });
        return true;
    }
    false
}

/// The screen we share, for Annotate (its size in device pixels).
fn shared_screen() -> cs::SharedScreen {
    let s = presenting::share_screen();
    let (w, h) = teams_cli::calling::screencast::last_size().unwrap_or(((s.width * s.dpr) as u32, (s.full_height * s.dpr) as u32));
    cs::SharedScreen { width: w, height: h, window: false }
}

/// Find the content and add the session (in the background).
async fn start_content(kind: &str, args: &serde_json::Value, title: &str, me_oid: &str) -> anyhow::Result<(cs::Session, String)> {
    let client = TeamsClient::new().await?;
    let (thread, message, organizer, participant) = {
        let slot = call_slot().lock().await;
        let call = slot.outgoing.as_ref().context("Not in a meeting")?;
        anyhow::ensure!(call.can_share_content(), "This call can't share content");
        (
            call.thread().to_string(),
            call.message_id().to_string(),
            call.organizer_oid().unwrap_or(me_oid).to_string(),
            call.participant_id().to_string(),
        )
    };
    let now = chrono::Utc::now().timestamp_millis();
    // A file named in your OneDrive's root (the harness): its ids.
    let mut args = args.clone();
    if let Some(name) = args.get("name").and_then(|n| n.as_str()).filter(|n| !n.is_empty()).map(str::to_string)
        && args.get("itemId").and_then(|i| i.as_str()).is_none_or(str::is_empty)
    {
        let path = teams_cli::api::tabs::encode_uri_component(&name);
        let v: serde_json::Value = client.graph_get(&format!("/me/drive/root:/{path}?$select=id,webUrl,webDavUrl,parentReference")).await?.json().await?;
        let s = |p: &str| v.pointer(p).and_then(|x| x.as_str()).unwrap_or_default().to_string();
        args["driveId"] = s("/parentReference/driveId").into();
        args["itemId"] = s("/id").into();
        args["url"] = s("/webDavUrl").into();
    }
    let args = &args;
    let mut board = String::new();
    let (content, subject, state) = match kind {
        // Teams' WhiteboardProvider: the meeting's own board (fluidboard),
        // with who started it and when.
        "whiteboard" => {
            let meeting = api::app_host::meeting_board(&client, &thread, &organizer, title).await?;
            let url = format!("{meeting}{}initiatorId={me_oid}&initiatorTimestamp={now}", if meeting.contains('?') { "&" } else { "?" });
            board = url.clone();
            (cs::whiteboard_content(&thread, &message, &url, &participant), String::new(), None)
        }
        // Annotate: the meeting's annotation board (beta/meetings/annotation),
        // its address sent once Whiteboard reports it.
        "annotation" => {
            let url = api::app_host::meeting_annotation_board(&client, &thread, &organizer, title).await?;
            let sep = if url.contains('?') { "&" } else { "?" };
            let with_flag = if url.contains("annotation=true") { url.clone() } else { format!("{url}{sep}annotation=true") };
            let initiated = format!("{with_flag}&initiatorId={me_oid}&initiatorTimestamp={now}");
            let screen = shared_screen();
            let (share_url, content_url) = cs::annotation_urls(&initiated, screen, "linux", &uuid::Uuid::new_v4().to_string());
            board = share_url.clone();
            (cs::annotation_content(&thread, &message, &share_url, &content_url), String::new(), None)
        }
        // PowerPoint Live (Teams' startFileSharing1): redeem the deck, ask
        // PowerPoint's snap service for the presentation, then the session
        // with the deck as its content and its name as the subject.
        "ppt" => {
            let url = args.get("url").and_then(|u| u.as_str()).unwrap_or_default().to_string();
            let url = if url.is_empty() {
                let (d, i) = (args.get("driveId").and_then(|x| x.as_str()).unwrap_or_default(), args.get("itemId").and_then(|x| x.as_str()).unwrap_or_default());
                let v: serde_json::Value = client.graph_get(&format!("/drives/{d}/items/{i}?$select=webUrl,webDavUrl")).await?.json().await?;
                v.get("webDavUrl").or_else(|| v.get("webUrl")).and_then(|u| u.as_str()).unwrap_or_default().to_string()
            } else {
                url
            };
            let item = api::live_share::redeem(&url).await?;
            let correlation = uuid::Uuid::new_v4().to_string();
            let mut file = api::live_share::ppt_file(&item, &correlation, now as u64)?;
            let call_id = call_slot().lock().await.outgoing.as_ref().map(|c| c.call_id().to_string()).unwrap_or_default();
            file.snap_url = api::live_share::snap_url(&file, &call_id).await?;
            let name = file.name.clone();
            (cs::ppt_content(&file), name, None)
        }
        // Excel Live (calling-app NP): the meeting's people get edit
        // access, Excel's meeting stage page hosts the workbook.
        "excel" => {
            let (d, i) = (args.get("driveId").and_then(|x| x.as_str()).unwrap_or_default(), args.get("itemId").and_then(|x| x.as_str()).unwrap_or_default());
            let people: Vec<String> = args.get("people").and_then(|p| p.as_array()).into_iter().flatten().filter_map(|p| p.as_str().map(str::to_string)).collect();
            let call_id = call_slot().lock().await.outgoing.as_ref().map(|c| c.call_id().to_string()).unwrap_or_default();
            let x = api::live_share::excel_share(&client, d, i, &people, &call_id).await?;
            let s = |k: &str| x.get(k).and_then(|v| v.as_str()).unwrap_or_default().to_string();
            let content = cs::excel_content(&thread, &message, &s("url"), "Excel", &s("fileId"), &s("substrateId"));
            // Teams names the presenter first among who may open it.
            let mut permitted = vec![me_oid.to_string()];
            permitted.extend(people.iter().filter(|p| p.as_str() != me_oid).cloned());
            let state = cs::excel_state(&permitted, &s("fileId"));
            (content, String::new(), Some(state))
        }
        "content" => {
            // A prepared content DTO (PowerPoint Live, Excel Live: the call
            // window builds them from the file).
            let c = args.get("content").cloned().context("No content")?;
            let subject = args.get("subject").and_then(|s| s.as_str()).unwrap_or_default().to_string();
            let state = args.get("state").and_then(|s| s.as_str()).map(str::to_string);
            (c, subject, state)
        }
        other => anyhow::bail!("Can't present {other}"),
    };
    let mut slot = call_slot().lock().await;
    let call = slot.outgoing.as_mut().context("Not in a meeting")?;
    call.start_content_sharing(content, &subject, state.as_deref()).await?;
    let s = call.my_content().cloned().context("The session didn't start")?;
    Ok((s, board))
}

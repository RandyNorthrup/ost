use cxx_qt_build::{CxxQtBuilder, QmlFile, QmlModule};

fn main() {
    let qml = [
        "qml/Main.qml",
        "qml/Theme.qml",
        "qml/FluentIcon.qml",
        "qml/TitleBar.qml",
        "qml/AppRail.qml",
        "qml/ChatList.qml",
        "qml/FilterMarks.qml",
        "qml/DiscoverView.qml",
        "qml/ListKeys.qml",
        "qml/LeaveChatDialog.qml",
        "qml/Conversation.qml",
        "qml/Avatar.qml",
        "qml/SignIn.qml",
        "qml/CallWindow.qml",
        "qml/CallsView.qml",
        "qml/CalendarView.qml",
        "qml/MeetView.qml",
        "qml/MeetingForm.qml",
        "qml/OutlookFormPane.qml",
        "qml/OutlookUploadTo.qml",
        "qml/OutlookAcceptableTimes.qml",
        "qml/OutlookEmailReminder.qml",
        "qml/OutlookNewCategory.qml",
        "qml/OutlookEditorSettings.qml",
        "qml/NewChat.qml",
        "qml/ChannelPosts.qml",
        "qml/KeyboardShortcuts.qml",
        "qml/KeysTest.qml",
        "qml/KbDialogTest.qml",
        "qml/MenuKeysTest.qml",
        "qml/MentionsView.qml",
        "qml/PreJoin.qml",
        "qml/RoomHome.qml",
        "qml/RoomAutoExit.qml",
        "qml/OneDriveView.qml",
        "qml/PeopleView.qml",
        "qml/PersonalPeopleView.qml",
        "qml/ChannelFiles.qml",
        "qml/StoreView.qml",
        "qml/StoreButton.qml",
        "qml/QuantityBox.qml",
        "qml/DeviceDetailsDialog.qml",
        "qml/DeviceCartDialog.qml",
        "qml/ManageAppsView.qml",
        "qml/WebApp.qml",
        "qml/AppDetailsDialog.qml",
        "qml/ContextlessDialog.qml",
        "qml/AgentStore.qml",
        "qml/AboutBotDialog.qml",
        "qml/AppPermissionsDialog.qml",
        "qml/ShareForm.qml",
        "qml/AppCardFooter.qml",
        "qml/SectionDialog.qml",
        "qml/RoundedCorners.qml",
        "qml/DraftsView.qml",
        "qml/ActivityView.qml",
        "qml/SettingsView.qml",
        "qml/EmojiPicker.qml",
        "qml/PresenceBadge.qml",
        "qml/MenuPopup.qml",
        "qml/FluentSurface.qml",
        "qml/Emoticon.qml",
        "qml/QuoteCard.qml",
        "qml/ReactionPicker.qml",
        "qml/ShareContactDialog.qml",
        "qml/FormatBar.qml",
        "qml/PeopleTagPicker.qml",
        "qml/AddPeopleDialog.qml",
        "qml/EmojiPanel.qml",
        "qml/FunPicker.qml",
        "qml/CustomEmojiAdd.qml",
        "qml/ForwardCard.qml",
        "qml/ForwardDialog.qml",
        "qml/ReportDialog.qml",
        "qml/WhoReacted.qml",
        "qml/CustomizeReactions.qml",
        "qml/ComposeBox.qml",
        "qml/EditorCard.qml",
        "qml/AdaptiveCard.qml",
        "qml/HeroCard.qml",
        "qml/HoverBar.qml",
        "qml/ReactionSummary.qml",
        "qml/BarButton.qml",
        "qml/PressedLine.qml",
        "qml/LimitTip.qml",
        "qml/UnverifiedBadge.qml",
        "qml/GuestAvatar.qml",
        "qml/LobbyToast.qml",
        "qml/MeetingTile.qml",
        "qml/BotAvatar.qml",
        "qml/CallQualitySurvey.qml",
        "qml/RetryScreen.qml",
        "qml/MeetingOptionsDialog.qml",
        "qml/MeetingPeoplePicker.qml",
        "qml/ArrowTip.qml",
        "qml/AttendanceCard.qml",
        "qml/AttendanceView.qml",
        "qml/PostThread.qml",
        "qml/GalleryGrid.qml",
        "qml/SharedDisplayWindow.qml",
        "qml/RoomNotice.qml",
        "qml/UrlPreviewCard.qml",
        "qml/AppLinkCard.qml",
        "qml/AppAuthWindow.qml",
        "qml/ChannelAgentToast.qml",
        "qml/SmartReplyFeedback.qml",
        "qml/AutoLocationDialog.qml",
        "qml/MobileAppDialog.qml",
        "qml/PremiumDialog.qml",
        "qml/CastWindow.qml",
        "qml/DownloadsFlyout.qml",
        "qml/MutedNotice.qml",
        "qml/CompactCallWindow.qml",
        "qml/AdmitSuspectedDialog.qml",
        "qml/PeoplePane.qml",
        "qml/ConfirmDialog.qml",
        "qml/PersonalRefusedDialog.qml",
        "qml/MeetingFileShareDialog.qml",
        "qml/LiveMeetingsDialog.qml",
        "qml/AudioFlyout.qml",
        "qml/NoiseSuppressionChoice.qml",
        "qml/InviteDialog.qml",
        "qml/AudioTestDialog.qml",
        "qml/MeetingChatPicker.qml",
        "qml/MeetingChatOptions.qml",
        "qml/LockMeetingDialog.qml",
        "qml/RoleChangeDialog.qml",
        "qml/VideoFlyout.qml",
        "qml/EffectTile.qml",
        "qml/VideoEffectsState.qml",
        "qml/VideoFilterHost.qml",
        "qml/AvatarHost.qml",
        "qml/AvatarNotice.qml",
        "qml/AvatarPicker.qml",
        "qml/AvatarCreate.qml",
        "qml/AvatarPanel.qml",
        "qml/NewChatWindow.qml",
        "qml/VideoEffectsPane.qml",
        "qml/NetworkPopover.qml",
        "qml/AiPopover.qml",
        "qml/MeetingInfoPane.qml",
        "qml/AudioSettingsPane.qml",
        "qml/RecordStartDialog.qml",
        "qml/TranscriptPane.qml",
        "qml/Dropdown.qml",
        "qml/RadioMenu.qml",
        "qml/CaptionsSettingsMenu.qml",
        "qml/CaptionsWindow.qml",
        "qml/CaptionStylesPane.qml",
        "qml/AccessibilityPane.qml",
        "qml/AssignRoomsDialog.qml",
        "qml/BreakoutCsvDialog.qml",
        "qml/BreakoutRoomsPane.qml",
        "qml/BreakoutTextDialog.qml",
        "qml/GreetingDialog.qml",
        "qml/CameraSettingsDialog.qml",
        "qml/CallAlert.qml",
        "qml/BreakoutInviteAlert.qml",
        "qml/ChatBubble.qml",
        "qml/MeetingReportDialog.qml",
        "qml/CaptionsPopout.qml",
        "qml/AppIcon.qml",
        "qml/TabAboutDialog.qml",
        "qml/TabConfigDialog.qml",
        "qml/TaskModuleDialog.qml",
        "qml/ShareToOutlookDialog.qml",
        "qml/ImmersiveReader.qml",
        "qml/EventsView.qml",
        "qml/EventPeoplePicker.qml",
        "qml/EventStagePreview.qml",
        "qml/MeetingRecapsView.qml",
        "qml/MeetingNotesPane.qml",
        "qml/PhoneAudioDialog.qml",
        "qml/ExistingPageDialog.qml",
        "qml/AiInterpreterDialog.qml",
        "qml/AiInterpreterModeDialog.qml",
        "qml/BreakoutSettingsDialog.qml",
        "qml/BreakoutTab.qml",
        "qml/TabWindow.qml",
        "qml/AppWindow.qml",
        "qml/CoreAppWindow.qml",
        "qml/MessageHost.qml",
        "qml/MessageStatusIcons.qml",
        "qml/CustomReminderDialog.qml",
        "qml/ReminderPresets.qml",
        "qml/ForwardSelectBar.qml",
        "qml/ForwardSelection.qml",
        "qml/SelectCheck.qml",
        "qml/LeaveSelectionDialog.qml",
        "qml/MessageText.qml",
        "qml/CodeBoxes.qml",
        "qml/ThreadWindow.qml",
        "qml/TabConversationPane.qml",
        "qml/ChannelMenu.qml",
        "qml/ChannelNotifyDialog.qml",
        "qml/ChannelEditDialog.qml",
        "qml/ChannelEmailDialog.qml",
        "qml/ChannelWindow.qml",
        "qml/WorkflowsDialog.qml",
        "qml/VideoClipCard.qml",
        "qml/LiveStreamPlayer.qml",
        "qml/VideoClipRecorder.qml",
        "qml/ClipCatalog.qml",
        "qml/ClipEffectsState.qml",
        "qml/ClipCanvasItems.qml",
        "qml/ClipEditOverlay.qml",
        "qml/ClipDrawer.qml",
        "qml/ClipEffectPanels.qml",
        "qml/ManageChannel.qml",
        "qml/ChannelModeration.qml",
        "qml/ModeratorsDialog.qml",
        "qml/AddMembersDialog.qml",
        "qml/ShareChannelDialog.qml",
        "qml/TagsView.qml",
        "qml/TagDialog.qml",
        "qml/TeamActionDialog.qml",
        "qml/MembersView.qml",
        "qml/PendingRequestsView.qml",
        "qml/TeamSettingsView.qml",
        "qml/TeamAppsView.qml",
        "qml/EditTeamDialog.qml",
        "qml/TeamPictureDialog.qml",
        "qml/AnalyticsView.qml",
        "qml/AnalyticsChart.qml",
        "qml/BannerImageDialog.qml",
        "qml/TeamMenu.qml",
        "qml/ManageTeam.qml",
        "qml/YourTeams.qml",
        "qml/TeamsAnalyticsTable.qml",
        "qml/CreateTeamDialog.qml",
        "qml/CreateTeamPage.qml",
        "qml/JoinTeamPage.qml",
        "qml/ChatWindow.qml",
        "qml/QuickListView.qml",
        "qml/DatePickerField.qml",
        "qml/OutlineDropdown.qml",
        "qml/SearchCombobox.qml",
        "qml/PauseNotificationsDialog.qml",
        "qml/SettingsParts.qml",
        "qml/OofPage.qml",
        "qml/ProfileCard.qml",
        "qml/HoverCard.qml",
        "qml/ListCard.qml",
        "qml/ConnectorCard.qml",
        "qml/AttachMenu.qml",
        "qml/CopilotPopover.qml",
        "qml/CloudPicker.qml",
        "qml/CloudAttach.qml",
        "qml/FileCard.qml",
        "qml/PersonalFilesTab.qml",
        "qml/PersonalPhotosTab.qml",
        "qml/PersonalCloudPicker.qml",
        "qml/CardResponseBar.qml",
        "qml/FileViewer.qml",
        "qml/PreviewBody.qml",
        "qml/ThreadsPane.qml",
        "qml/CopilotPane.qml",
        "qml/CopilotHistoryPane.qml",
        "qml/ScheduledMeetingCard.qml",
        "qml/FindPane.qml",
        "qml/ChannelMeetingsPane.qml",
        "qml/ChannelAudiencePopover.qml",
        "qml/FeedbackWindow.qml",
        "qml/HelpView.qml",
        "qml/HelpWindow.qml",
        "qml/SearchSuggest.qml",
        "qml/SearchView.qml",
        "qml/OneDriveShare.qml",
        "qml/OdspCopilotPane.qml",
        "qml/FileActions.qml",
        "qml/DetailsPane.qml",
        "qml/FilePreview.qml",
        "qml/PlaylistPicker.qml",
        "qml/SiteTile.qml",
        "qml/ShareFileDialog.qml",
        "qml/SearchPreview.qml",
        "qml/CreateChannelDialog.qml",
        "qml/CrossPostDialog.qml",
        "qml/RttBox.qml",
        "qml/ChildWindowTitleBar.qml",
        "qml/MeetingTimerStrip.qml",
        "qml/AgendaTimerRow.qml",
        "qml/CallHealthPane.qml",
        "qml/RoomRemotePane.qml",
        "qml/TimerSpin.qml",
        "qml/NotificationBanners.qml",
        "qml/EnrollmentDone.qml",
        "qml/FaceCaptureDialog.qml",
        "qml/VoiceCaptureDialog.qml",
        "qml/VoicemailTransferPicker.qml",
        "qml/ExternalBadge.qml",
        "qml/ChatRequestView.qml",
        "qml/RequestsView.qml",
        "qml/UnparkDialog.qml",
        "qml/ChatNotesTab.qml",
        "qml/LoopPage.qml",
        "qml/LoopCard.qml",
        "qml/LoopAccessPopover.qml",
        "qml/LoopChromeBar.qml",
        "qml/SuggestedActionsRow.qml",
        "qml/SeeMoreRules.qml",
        "qml/SeeMoreLink.qml",
        "qml/ReasoningBlock.qml",
        "qml/OdslBlock.qml",
        "qml/CodeCard.qml",
        "qml/OdslCards.qml",
        "qml/PostBody.qml",
        "qml/ImageLightbox.qml",
        "qml/LoopCommandingSurface.qml",
        "qml/RecapCard.qml",
        "qml/RecapWindow.qml",
        "qml/AudioRecapPlayer.qml",
        "qml/RecapShareDialog.qml",
        "qml/RecapTemplateEditor.qml",
        "qml/RecapTemplateNameDialog.qml",
        "qml/ComposeAppPanel.qml",
        "qml/ChannelPageTab.qml",
        "qml/RecapTab.qml",
        "qml/TestCallReport.qml",
        "qml/TestCallDevices.qml",
        "qml/ShareTray.qml",
        "qml/SharingControlBar.qml",
        "qml/ContentStage.qml",
        "qml/PptLiveStage.qml",
        "qml/AnnotationOverlay.qml",
        "qml/ControlAlert.qml",
        "qml/ContentCameraDialog.qml",
        "qml/MtmaHub.qml",
        "qml/CopilotUpsellView.qml",
        "qml/CommunitiesView.qml",
        "qml/PlansPage.qml",
        "qml/VideoTileMenu.qml",
    ];
    let mut resources: Vec<String> = Vec::new();
    for dir in [
        "assets/icons",
        "assets/fonts",
        "assets/tray",
        "assets/funstuff",
        "assets/lobby",
        "assets/dialogs",
        "assets/illustrations",
        "assets/settings",
        "assets/biometric",
        "assets/sounds",
        "assets/help",
    ] {
        for entry in std::fs::read_dir(dir).expect("asset dir") {
            let path = entry.expect("asset entry").path();
            if matches!(
                path.extension().and_then(|e| e.to_str()),
                Some("svg" | "ttf" | "png" | "jpg" | "json" | "mp3")
            ) {
                resources.push(path.to_string_lossy().into_owned());
            }
        }
    }
    resources.push("assets/logo.png".into());
    // OST's strings keyed to Teams' string ids (i18n/l10n.py writes them;
    // the engine's translator, teams_cli::i18n, compiles them in). The
    // translations are built on the device from Teams' own resources
    // (api::teams_strings).
    println!("cargo:rerun-if-changed=i18n/ids.json");
    println!("cargo:rerun-if-changed=i18n/teams_resources.json");
    // Help (F1): the articles in docs/help, compiled in (Help works
    // offline); OUT_DIR/help_files.rs lists them for src/help_bundle.rs.
    {
        let root = std::path::Path::new("../docs/help");
        println!("cargo:rerun-if-changed=../docs/help");
        let mut files: Vec<(String, std::path::PathBuf)> = Vec::new();
        if let Ok(cats) = std::fs::read_dir(root) {
            for cat in cats.flatten() {
                if !cat.path().is_dir() {
                    continue;
                }
                println!("cargo:rerun-if-changed={}", cat.path().display());
                for f in std::fs::read_dir(cat.path())
                    .into_iter()
                    .flatten()
                    .flatten()
                {
                    let p = f.path();
                    if p.extension().and_then(|e| e.to_str()) == Some("md") {
                        let rel = format!(
                            "{}/{}",
                            cat.file_name().to_string_lossy(),
                            f.file_name().to_string_lossy()
                        );
                        files.push((rel, std::fs::canonicalize(&p).expect("help article")));
                    }
                }
            }
        }
        files.sort();
        let list: String = files
            .iter()
            .map(|(rel, abs)| {
                format!(
                    "    ({rel:?}, include_str!({:?})),\n",
                    abs.display().to_string()
                )
            })
            .collect();
        let out = std::path::PathBuf::from(std::env::var("OUT_DIR").expect("OUT_DIR"))
            .join("help_files.rs");
        std::fs::write(
            out,
            format!("pub static FILES: &[(&str, &str)] = &[\n{list}];\n"),
        )
        .expect("help_files.rs");
    }
    resources.sort();
    let module = QmlModule::new("com.ost.desktop")
        .qml_files(qml)
        .qml_file(QmlFile::from("qml/IconCache.qml").singleton(true))
        .qml_file(QmlFile::from("qml/Mri.qml").singleton(true));
    // qt-build-utils runs qmlcachegen before qmltyperegistrar writes this
    // build's plugin.qmltypes, so an incremental build would compile the
    // QML against the previous build's types: after a Rust QObject gains a
    // property or method, the compiled QML calls the wrong meta-method
    // index and crashes. Without the old file, every build compiles as a
    // clean one does.
    if let Some(out) = std::env::var_os("OUT_DIR") {
        let stale = std::path::Path::new(&out)
            .join("qt-build-utils/qml_modules/com/ost/desktop/plugin.qmltypes");
        let _ = std::fs::remove_file(stale);
    }
    // The clip recorder's effects are fragment shaders (shaders/*.frag),
    // baked for Qt's RHI with qsb (Debian/Ubuntu: qt6-shader-baker; Arch:
    // qt6-shadertools) into OUT_DIR and served beside the QML as
    // shaders/<name>.frag.qsb.
    let shader_qrc = bake_shaders();
    // Qt WebEngine comes with Qt's installation, or from a prefix of its own
    // (see webengine_apart).
    let webengine = webengine_apart();
    let builder = CxxQtBuilder::new_qml_module(module)
        .file("src/backend.rs")
        .file("src/video_item.rs")
        .file("src/key_typer.rs")
        .file("src/window_tool.rs")
        .file("src/rich_text.rs")
        .file("src/clip_frames.rs")
        .file("src/clip_mask.rs")
        .file("src/camera_feed.rs")
        .qt_module("Quick")
        .qt_module("QuickControls2")
        .qt_module("Multimedia")
        .qrc_resources(resources)
        .qrc(&shader_qrc);
    let builder = if webengine.is_none() {
        builder.qt_module("WebEngineQuick")
    } else {
        builder
    };
    let webengine_includes: Vec<std::path::PathBuf> =
        webengine.map(|l| l.include_paths).unwrap_or_default();
    // SAFETY: only adds source files and include paths to the C++ build.
    let builder = unsafe {
        builder.cc_builder(|cc| {
            for p in &webengine_includes {
                cc.include(p);
            }
            cc.file("src/webengine.cpp");
            cc.file("src/native.cpp");
            cc.file("src/i18n.cpp");
            cc.file("src/richtext.cpp");
            cc.file("src/clipframes.cpp");
            cc.file("src/clipmask.cpp");
            cc.file("src/camerafeed.cpp");
            cc.file("src/clipedit.cpp");
            cc.file("src/vfxplayer.cpp");
            cc.file("src/vfxpicture.cpp");
        })
    };
    println!("cargo::rerun-if-changed=src/webengine.cpp");
    println!("cargo::rerun-if-changed=src/native.cpp");
    println!("cargo::rerun-if-changed=src/i18n.cpp");
    println!("cargo::rerun-if-changed=src/richtext.cpp");
    println!("cargo::rerun-if-changed=src/clipframes.cpp");
    println!("cargo::rerun-if-changed=src/clipmask.cpp");
    println!("cargo::rerun-if-changed=src/camerafeed.cpp");
    println!("cargo::rerun-if-changed=src/clipedit.cpp");
    println!("cargo::rerun-if-changed=src/vfxplayer.cpp");
    println!("cargo::rerun-if-changed=src/vfxpicture.cpp");
    // The clip editor renders, and video backgrounds play, with FFmpeg's
    // libraries (as Qt Multimedia does).
    for lib in ["avfilter", "avformat", "avcodec", "avutil", "swscale"] {
        println!("cargo::rustc-link-lib={lib}");
    }
    // FFmpeg's headers where a distribution keeps them outside the default
    // include path (openSUSE: /usr/include/ffmpeg), as its pkg-config says.
    let ffmpeg_includes: Vec<String> = std::process::Command::new("pkg-config")
        .arg("--cflags-only-I")
        .args([
            "libavfilter",
            "libavformat",
            "libavcodec",
            "libavutil",
            "libswscale",
        ])
        .output()
        .ok()
        .filter(|o| o.status.success())
        .map(|o| {
            String::from_utf8_lossy(&o.stdout)
                .split_whitespace()
                .filter_map(|f| f.strip_prefix("-I"))
                .map(str::to_string)
                .collect()
        })
        .unwrap_or_default();
    // SAFETY: only adds include paths to the C++ build.
    let builder = unsafe {
        builder.cc_builder(|cc| {
            for p in &ffmpeg_includes {
                cc.include(p);
            }
        })
    };
    builder.build();
}

/// Bake shaders/*.frag with Qt's qsb; the .qrc listing them.
fn bake_shaders() -> std::path::PathBuf {
    let out = std::path::PathBuf::from(std::env::var("OUT_DIR").expect("OUT_DIR")).join("shaders");
    std::fs::create_dir_all(&out).expect("shader dir");
    println!("cargo::rerun-if-changed=shaders");
    let qsb = find_qsb().expect("qsb (Qt Shader Tools) is needed to build OST: install qt6-shader-baker (Debian/Ubuntu) or qt6-shadertools (Arch)");
    let mut files: Vec<String> = Vec::new();
    let mut entries: Vec<_> = std::fs::read_dir("shaders")
        .expect("shaders")
        .flatten()
        .map(|e| e.path())
        .collect();
    entries.sort();
    for src in entries {
        if src.extension().and_then(|e| e.to_str()) != Some("frag") {
            continue;
        }
        println!("cargo::rerun-if-changed={}", src.display());
        let name = format!("{}.qsb", src.file_name().unwrap().to_string_lossy());
        let dst = out.join(&name);
        let ok = std::process::Command::new(&qsb)
            .args([
                "--glsl",
                "100es,120,150",
                "--hlsl",
                "50",
                "--msl",
                "12",
                "-o",
            ])
            .arg(&dst)
            .arg(&src)
            .status()
            .map(|s| s.success())
            .unwrap_or(false);
        assert!(ok, "qsb failed on {}", src.display());
        files.push(format!(
            "    <file alias=\"shaders/{name}\">{}</file>\n",
            dst.display()
        ));
    }
    let qrc = out.join("shaders.qrc");
    std::fs::write(
        &qrc,
        format!(
            "<RCC>\n  <qresource prefix=\"/qt/qml/com/ost/desktop\">\n{}  </qresource>\n</RCC>\n",
            files.concat()
        ),
    )
    .expect("shaders.qrc");
    qrc
}

/// Qt's qmake -query values for `key`: from $QMAKE (as cxx-qt-build uses
/// it), qmake6 and qmake.
fn qmake_query(key: &str) -> Vec<String> {
    println!("cargo::rerun-if-env-changed=QMAKE");
    let mut qmakes: Vec<std::ffi::OsString> = Vec::new();
    if let Some(q) = std::env::var_os("QMAKE").filter(|q| !q.is_empty()) {
        qmakes.push(q);
    }
    qmakes.extend(["qmake6", "qmake"].map(std::ffi::OsString::from));
    let mut out = Vec::new();
    for qmake in qmakes {
        if let Ok(o) = std::process::Command::new(&qmake)
            .args(["-query", key])
            .output()
            && o.status.success()
        {
            let d = String::from_utf8_lossy(&o.stdout).trim().to_string();
            if !d.is_empty() && !out.contains(&d) {
                out.push(d);
            }
        }
    }
    out
}

/// Qt WebEngine installed in a prefix of its own, outside Qt's installation:
/// Flathub's QtWebEngine BaseApp puts it in /app beside the KDE runtime's Qt
/// in /usr. Qt's installation then has no .prl file for it (cxx-qt-build
/// links Qt modules by those), so it is linked from its pkg-config file
/// instead. None where Qt's installation has it, as on distributions.
fn webengine_apart() -> Option<pkg_config::Library> {
    let libs = qmake_query("QT_INSTALL_LIBS");
    let first = libs.first()?;
    if std::path::Path::new(first)
        .join("libQt6WebEngineQuick.prl")
        .exists()
    {
        return None;
    }
    pkg_config::Config::new().probe("Qt6WebEngineQuick").ok()
}

fn find_qsb() -> Option<std::path::PathBuf> {
    let mut dirs: Vec<std::path::PathBuf> = Vec::new();
    for key in [
        "QT_HOST_BINS",
        "QT_HOST_LIBEXECS",
        "QT_INSTALL_BINS",
        "QT_INSTALL_LIBEXECS",
    ] {
        dirs.extend(qmake_query(key).into_iter().map(std::path::PathBuf::from));
    }
    dirs.extend(
        [
            "/usr/lib/qt6/bin",
            "/usr/lib/qt6/libexec",
            "/usr/lib/x86_64-linux-gnu/qt6/bin",
            "/usr/lib/x86_64-linux-gnu/qt6/libexec",
        ]
        .map(std::path::PathBuf::from),
    );
    if let Some(path) = std::env::var_os("PATH") {
        dirs.extend(std::env::split_paths(&path));
    }
    dirs.into_iter()
        .map(|d| d.join("qsb"))
        .find(|p| p.is_file())
}

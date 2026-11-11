use cxx_qt_build::{CxxQtBuilder, QmlFile, QmlModule};

fn main() {
    let qml = [
        "qml/Main.qml",
        "qml/Theme.qml",
        "qml/FluentIcon.qml",
        "qml/TitleBar.qml",
        "qml/AppRail.qml",
        "qml/ChatList.qml",
        "qml/Conversation.qml",
        "qml/Avatar.qml",
        "qml/SignIn.qml",
        "qml/IncomingCall.qml",
        "qml/CallWindow.qml",
        "qml/CallsView.qml",
        "qml/CalendarView.qml",
        "qml/NewChat.qml",
        "qml/ChannelPosts.qml",
        "qml/KeyboardShortcuts.qml",
        "qml/KeysTest.qml",
        "qml/MentionsView.qml",
        "qml/PreJoin.qml",
        "qml/OneDriveView.qml",
        "qml/PlannerView.qml",
        "qml/PeopleView.qml",
        "qml/OneNoteView.qml",
        "qml/ChannelFiles.qml",
        "qml/StoreView.qml",
        "qml/WebApp.qml",
        "qml/AppDetailsDialog.qml",
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
        "qml/RetryScreen.qml",
        "qml/MeetingOptionsDialog.qml",
        "qml/PostThread.qml",
        "qml/GalleryGrid.qml",
        "qml/SharedDisplayWindow.qml",
        "qml/RoomNotice.qml",
        "qml/MutedNotice.qml",
        "qml/CompactCallWindow.qml",
        "qml/AdmitSuspectedDialog.qml",
        "qml/PeoplePane.qml",
        "qml/ConfirmDialog.qml",
        "qml/AudioFlyout.qml",
        "qml/InviteDialog.qml",
        "qml/LockMeetingDialog.qml",
        "qml/RoleChangeDialog.qml",
        "qml/VideoFlyout.qml",
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
        "qml/ChatBubble.qml",
        "qml/MeetingReportDialog.qml",
        "qml/CaptionsPopout.qml",
        "qml/AppIcon.qml",
        "qml/TabAboutDialog.qml",
        "qml/TabWindow.qml",
        "qml/MessageHost.qml",
        "qml/MessageText.qml",
        "qml/ThreadWindow.qml",
        "qml/TabConversationPane.qml",
        "qml/ChannelMenu.qml",
        "qml/ChannelNotifyDialog.qml",
        "qml/ChannelEditDialog.qml",
        "qml/ChannelEmailDialog.qml",
        "qml/ChannelWindow.qml",
        "qml/WorkflowsDialog.qml",
        "qml/ManageChannel.qml",
        "qml/ChannelModeration.qml",
        "qml/ModeratorsDialog.qml",
        "qml/AddMembersDialog.qml",
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
        "qml/PauseNotificationsDialog.qml",
        "qml/SettingsParts.qml",
        "qml/OofPage.qml",
        "qml/ProfileCard.qml",
        "qml/ThreadsPane.qml",
        "qml/FindPane.qml",
        "qml/FeedbackWindow.qml",
        "qml/HelpView.qml",
        "qml/HelpWindow.qml",
        "qml/SearchView.qml",
        "qml/SearchPreview.qml",
        "qml/CreateChannelDialog.qml",
        "qml/RttBox.qml",
        "qml/ChildWindowTitleBar.qml",
        "qml/MeetingTimerStrip.qml",
        "qml/CallHealthPane.qml",
        "qml/TimerSpin.qml",
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
        "assets/help",
    ] {
        for entry in std::fs::read_dir(dir).expect("asset dir") {
            let path = entry.expect("asset entry").path();
            if matches!(
                path.extension().and_then(|e| e.to_str()),
                Some("svg" | "ttf" | "png" | "json")
            ) {
                resources.push(path.to_string_lossy().into_owned());
            }
        }
    }
    resources.push("assets/logo.png".into());
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
                for f in std::fs::read_dir(cat.path()).into_iter().flatten().flatten() {
                    let p = f.path();
                    if p.extension().and_then(|e| e.to_str()) == Some("md") {
                        let rel = format!("{}/{}", cat.file_name().to_string_lossy(), f.file_name().to_string_lossy());
                        files.push((rel, std::fs::canonicalize(&p).expect("help article")));
                    }
                }
            }
        }
        files.sort();
        let list: String = files
            .iter()
            .map(|(rel, abs)| format!("    ({rel:?}, include_str!({:?})),\n", abs.display().to_string()))
            .collect();
        let out = std::path::PathBuf::from(std::env::var("OUT_DIR").expect("OUT_DIR")).join("help_files.rs");
        std::fs::write(out, format!("pub static FILES: &[(&str, &str)] = &[\n{list}];\n")).expect("help_files.rs");
    }
    resources.sort();
    let module = QmlModule::new("com.ost.desktop")
        .qml_files(qml)
        .qml_file(QmlFile::from("qml/IconCache.qml").singleton(true));
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
    let builder = CxxQtBuilder::new_qml_module(module)
        .file("src/backend.rs")
        .file("src/video_item.rs")
        .file("src/key_typer.rs")
        .file("src/rich_text.rs")
        .qt_module("Quick")
        .qt_module("QuickControls2")
        .qt_module("WebEngineQuick")
        .qrc_resources(resources);
    // SAFETY: only adds a source file to the C++ build.
    let builder = unsafe {
        builder.cc_builder(|cc| {
            cc.file("src/webengine.cpp");
            cc.file("src/native.cpp");
            cc.file("src/richtext.cpp");
        })
    };
    println!("cargo::rerun-if-changed=src/webengine.cpp");
    println!("cargo::rerun-if-changed=src/native.cpp");
    println!("cargo::rerun-if-changed=src/richtext.cpp");
    builder.build();
}

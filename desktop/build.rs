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
        "qml/AdmitSuspectedDialog.qml",
        "qml/PeoplePane.qml",
        "qml/EndMeetingDialog.qml",
        "qml/AudioFlyout.qml",
    ];
    let mut resources: Vec<String> = Vec::new();
    for dir in [
        "assets/icons",
        "assets/fonts",
        "assets/tray",
        "assets/funstuff",
        "assets/lobby",
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
    resources.sort();
    let module = QmlModule::new("com.ost.desktop")
        .qml_files(qml)
        .qml_file(QmlFile::from("qml/IconCache.qml").singleton(true));
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

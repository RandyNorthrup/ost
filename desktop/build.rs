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
        "qml/RoundedCorners.qml",
        "qml/DraftsView.qml",
        "qml/ActivityView.qml",
        "qml/SettingsView.qml",
        "qml/EmojiPicker.qml",
        "qml/PresenceBadge.qml",
        "qml/MenuPopup.qml",
    ];
    let mut resources: Vec<String> = Vec::new();
    for dir in ["assets/icons", "assets/fonts"] {
        for entry in std::fs::read_dir(dir).expect("asset dir") {
            let path = entry.expect("asset entry").path();
            if matches!(
                path.extension().and_then(|e| e.to_str()),
                Some("svg" | "ttf")
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
    CxxQtBuilder::new_qml_module(module)
        .file("src/backend.rs")
        .file("src/video_item.rs")
        .qt_module("Quick")
        .qt_module("QuickControls2")
        .qrc_resources(resources)
        .build();
}

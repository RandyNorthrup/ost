// QtWebEngine must be set up before the QGuiApplication exists (it
// shares an OpenGL context with Qt Quick); cxx-qt-lib has no binding for
// it, so this one call is plain C++.
#include <QtWebEngineQuick/qtwebenginequickglobal.h>
#include <QtCore/QCoreApplication>
#include <QtWidgets/QApplication>
#include <QtGui/QKeyEvent>
#include <QtQuick/QQuickItem>
#include <QtQuick/QQuickWindow>

extern "C" void ost_webengine_initialize()
{
    QtWebEngineQuick::initialize();
}

// The application object. A QApplication, not just a QGuiApplication:
// Qt Labs Platform's tray menu falls back to a widget menu where the
// platform has no native one (Plasma), and that needs Qt Widgets.
// `phase(data, 0)` runs once the application exists, `phase(data, 1)`
// after its event loop, while it still exists. Returns exec()'s exit code.
// `argc` and `argv` (the command line) must outlive the call.
extern "C" int ost_application_run(int *argc, char **argv, const char *name,
                                   const char *version, const char *desktop_file,
                                   void (*phase)(void *, int), void *data)
{
    QApplication app(*argc, argv);
    QGuiApplication::setDesktopFileName(QString::fromUtf8(desktop_file));
    QCoreApplication::setApplicationName(QString::fromUtf8(name));
    QCoreApplication::setApplicationVersion(QString::fromUtf8(version));
    phase(data, 0);
    const int code = app.exec();
    phase(data, 1);
    return code;
}

// Type text into the window of `item` (a KeyTyper) as real key presses:
// what has focus there (a web view) gets them as typing.
extern "C" void ost_type_keys(void *item, const char *utf8)
{
    auto *it = static_cast<QQuickItem *>(item);
    QQuickWindow *window = it ? it->window() : nullptr;
    if (!window)
        return;
    for (const QChar c : QString::fromUtf8(utf8)) {
        int key = c.toUpper().unicode();
        QString text(c);
        Qt::KeyboardModifiers mods = Qt::NoModifier;
        if (c == u'\u0001') {
            // Ctrl+End: to the end of the document.
            key = Qt::Key_End;
            mods = Qt::ControlModifier;
            text.clear();
        } else if (c == u'\n') {
            key = Qt::Key_Return;
            text = QStringLiteral("\r");
        } else if (c == u'/') {
            key = Qt::Key_Slash;
        } else if (c == u' ') {
            key = Qt::Key_Space;
        }
        QKeyEvent press(QEvent::KeyPress, key, mods, text);
        QCoreApplication::sendEvent(window, &press);
        QKeyEvent release(QEvent::KeyRelease, key, mods, text);
        QCoreApplication::sendEvent(window, &release);
    }
}

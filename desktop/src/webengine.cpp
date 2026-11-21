// QtWebEngine must be set up before the QGuiApplication exists (it
// shares an OpenGL context with Qt Quick); cxx-qt-lib has no binding for
// it, so this one call is plain C++.
#include <QtWebEngineQuick/qtwebenginequickglobal.h>
#include <QtCore/QCoreApplication>
#include <QtGui/QKeyEvent>
#include <QtGui/QMouseEvent>
#include <QtQuick/QQuickItem>
#include <QtQuick/QQuickWindow>

extern "C" void ost_webengine_initialize()
{
    QtWebEngineQuick::initialize();
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
        } else if (c == u'\u0002') {
            // Shift+Home: select to the start of the line.
            key = Qt::Key_Home;
            mods = Qt::ShiftModifier;
            text.clear();
        } else if (c == u'\u0003') {
            // Shift+F10: the context menu.
            key = Qt::Key_F10;
            mods = Qt::ShiftModifier;
            text.clear();
        } else if (c == u'\u0016') {
            // Ctrl+V: paste.
            key = Qt::Key_V;
            mods = Qt::ControlModifier;
            text.clear();
        } else if (c == u'\u001a') {
            // Ctrl+Z: undo.
            key = Qt::Key_Z;
            mods = Qt::ControlModifier;
            text.clear();
        } else if (c == u'\u001b') {
            key = Qt::Key_Escape;
            text = QStringLiteral("\x1b");
        } else if (c == u'\b') {
            key = Qt::Key_Backspace;
            text = QStringLiteral("\b");
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

// Drag the mouse with the left button held across `item`'s window, from
// (x1, y1) to (x2, y2) in the item's coordinates, as a mouse would (a
// press, moves, a release): a text selection in a web view. Only this
// window gets the events.
extern "C" void ost_mouse_drag(void *item, double x1, double y1, double x2, double y2)
{
    auto *it = static_cast<QQuickItem *>(item);
    QQuickWindow *window = it ? it->window() : nullptr;
    if (!window)
        return;
    auto send = [&](QEvent::Type type, QPointF local, Qt::MouseButton button, Qt::MouseButtons buttons) {
        const QPointF scene = it->mapToScene(local);
        QMouseEvent e(type, scene, scene, window->mapToGlobal(scene), button, buttons, Qt::NoModifier);
        QCoreApplication::sendEvent(window, &e);
    };
    send(QEvent::MouseMove, QPointF(x1, y1), Qt::NoButton, Qt::NoButton);
    send(QEvent::MouseButtonPress, QPointF(x1, y1), Qt::LeftButton, Qt::LeftButton);
    for (int i = 1; i <= 8; ++i)
        send(QEvent::MouseMove, QPointF(x1 + (x2 - x1) * i / 8, y1 + (y2 - y1) * i / 8), Qt::NoButton, Qt::LeftButton);
    send(QEvent::MouseButtonRelease, QPointF(x2, y2), Qt::LeftButton, Qt::NoButton);
}

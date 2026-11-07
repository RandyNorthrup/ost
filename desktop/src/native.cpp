// Small native helpers cxx-qt-lib has no binding for.
#include <QtCore/QMimeData>
#include <QtGui/QClipboard>
#include <QtGui/QGuiApplication>

// Put `text` on the clipboard with an HTML form, as Teams copies links
// (the HTML carries the name the link reads as).
extern "C" void ost_set_clipboard(const char *text, const char *html)
{
    auto *mime = new QMimeData;
    mime->setText(QString::fromUtf8(text));
    if (html && *html)
        mime->setHtml(QString::fromUtf8(html));
    QGuiApplication::clipboard()->setMimeData(mime);
}

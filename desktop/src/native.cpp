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

#include <QtGui/QImage>

// Put the picture in `path` on the clipboard (Report a problem's
// screenshot, to paste into the GitHub issue). Whether it could be read.
extern "C" bool ost_set_clipboard_image(const char *path)
{
    QImage image(QString::fromUtf8(path));
    if (image.isNull())
        return false;
    QGuiApplication::clipboard()->setImage(image);
    return true;
}

// Save the clipboard's picture as a PNG at `path` (pasting a screenshot
// into Report a problem). Whether there was one.
extern "C" bool ost_save_clipboard_image(const char *path)
{
    const QImage image = QGuiApplication::clipboard()->image();
    return !image.isNull() && image.save(QString::fromUtf8(path), "PNG");
}

#include <QtGui/QFont>
#include <QtGui/QFontMetricsF>
#include <QtGui/QPixmap>
#include <QtGui/QIcon>
#include <QtGui/QImage>
#include <QtGui/QImageReader>
#include <QtGui/QPainter>
#include <QtGui/QWindow>

// Teams' taskbar badge (Windows' overlay on the taskbar button, measured
// on winpc, 2026-11-08): a 16 px overlay on the 24 px icon, bottom-right.
// With anything unread it is the count on a #C42B1C circle in white
// (Windows' numeric badge: 1-99, then "99+"); with nothing unread it is
// your presence glyph in a white ring (Away #EAA300, Busy and Do not
// disturb #C50F1F). OST draws the same overlay into its window icon at
// each size, so taskbars that show a window's own icon (KDE via
// xdg-toplevel-icon, X11 via _NET_WM_ICON) show it as Teams' does.
static QImage ost_badged_icon(const QImage &logo, int size, int count, const QString &kind)
{
    QImage img(size, size, QImage::Format_ARGB32_Premultiplied);
    img.fill(Qt::transparent);
    QPainter p(&img);
    p.setRenderHint(QPainter::Antialiasing);
    p.setRenderHint(QPainter::SmoothPixmapTransform);
    // Windows sets the 16 px overlay 1.33 px past the 24 px icon's
    // bottom-right corner (measured at 150%: 24 px circle, 36 px icon):
    // the logo takes 22.67/24 of the canvas, the overlay the corner.
    const qreal logoSize = size * 22.67 / 24.0;
    p.drawImage(QRectF(0, 0, logoSize, logoSize), logo);
    const qreal d = size * 16.0 / 24.0;
    if (count > 0) {
        const QString text = count > 99 ? QStringLiteral("99+") : QString::number(count);
        QFont f(QStringLiteral("Selawik"));
        f.setPixelSize(qMax(6, int(d * 0.56 + 0.5)));
        f.setWeight(QFont::Normal);
        const qreal tw = QFontMetricsF(f).horizontalAdvance(text);
        const qreal w = qMax(d, tw + d * 0.5);
        const QRectF r(size - w, size - d, w, d);
        p.setPen(Qt::NoPen);
        p.setBrush(QColor(0xC4, 0x2B, 0x1C));
        p.drawRoundedRect(r, d / 2, d / 2);
        p.setPen(Qt::white);
        p.setFont(f);
        p.drawText(r, Qt::AlignCenter, text);
    } else if (!kind.isEmpty() && kind != QLatin1String("unknown")) {
        QColor ink(0x61, 0x61, 0x61);
        if (kind == QLatin1String("available"))
            ink = QColor(0x13, 0xA1, 0x0E);
        else if (kind == QLatin1String("away"))
            ink = QColor(0xEA, 0xA3, 0x00);
        else if (kind == QLatin1String("busy") || kind == QLatin1String("dnd"))
            ink = QColor(0xC5, 0x0F, 0x1F);
        else if (kind == QLatin1String("oof"))
            ink = QColor(0xC2, 0x39, 0xB3);
        // The white ring, then the glyph inside it, tinted.
        const QRectF outer(size - d, size - d, d, d);
        p.setPen(Qt::NoPen);
        p.setBrush(Qt::white);
        p.drawEllipse(outer);
        const qreal ring = qMax(1.0, d / 16.0);
        const int g = qMax(1, int(d - 2 * ring));
        QImageReader reader(QStringLiteral(":/qt/qml/com/ost/desktop/assets/icons/presence-%1-16.svg").arg(kind));
        reader.setScaledSize(QSize(g, g));
        QImage glyph = reader.read();
        if (!glyph.isNull()) {
            glyph = glyph.convertToFormat(QImage::Format_ARGB32_Premultiplied);
            QPainter gp(&glyph);
            gp.setCompositionMode(QPainter::CompositionMode_SourceIn);
            gp.fillRect(glyph.rect(), ink);
            gp.end();
            p.drawImage(QPointF(size - d + ring, size - d + ring), glyph);
        }
    }
    p.end();
    return img;
}

extern "C" void ost_set_taskbar_badge(int count, const char *kind)
{
    static const QImage logo(QStringLiteral(":/qt/qml/com/ost/desktop/assets/logo.png"));
    if (logo.isNull())
        return;
    const QString k = QString::fromUtf8(kind ? kind : "");
    QIcon icon;
    for (int size : {16, 22, 24, 32, 48, 64, 96, 128, 256})
        icon.addPixmap(QPixmap::fromImage(ost_badged_icon(logo, size, count, k)));
    QGuiApplication::setWindowIcon(icon);
    for (QWindow *w : QGuiApplication::topLevelWindows())
        w->setIcon(icon);
    // OST_DUMP_BADGE=<dir>: save the 24 and 64 px icons (diagnostics).
    const QByteArray dump = qgetenv("OST_DUMP_BADGE");
    if (!dump.isEmpty()) {
        for (int size : {24, 64})
            ost_badged_icon(logo, size, count, k)
                .save(QStringLiteral("%1/badge-%2-%3-%4.png").arg(QString::fromLocal8Bit(dump)).arg(count).arg(k).arg(size));
    }
}

#include <QtGui/QDesktopServices>

// Settings ▸ Files and links ▸ "Always open web links in:": every http(s)
// link OST opens (Qt.openUrlExternally) goes to the backend's
// openWebLink, which starts the chosen browser.
extern "C" void ost_install_link_handler(QObject *backend)
{
    QDesktopServices::setUrlHandler(QStringLiteral("http"), backend, "openWebLink");
    QDesktopServices::setUrlHandler(QStringLiteral("https"), backend, "openWebLink");
}

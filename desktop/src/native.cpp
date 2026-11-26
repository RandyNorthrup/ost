// Small native helpers cxx-qt-lib has no binding for.
#include <QtCore/QMimeData>
#include <QtGui/QClipboard>
#include <QtGui/QGuiApplication>
#include <QtCore/QLocale>
#include <cstring>

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

#include <QtCore/QMimeData>

// A picture pasted into the compose box: when the clipboard holds a
// picture and no text, save it as a PNG at `path` and give its size.
// 1 saved, 0 no picture to paste (text goes in as text), -1 a picture
// that couldn't be read or saved.
extern "C" int ost_save_clipboard_picture(const char *path, int *width, int *height)
{
    const QMimeData *mime = QGuiApplication::clipboard()->mimeData();
    if (!mime || !mime->hasImage() || mime->hasText())
        return 0;
    const QImage image = qvariant_cast<QImage>(mime->imageData());
    if (image.isNull() || !image.save(QString::fromUtf8(path), "PNG"))
        return -1;
    *width = image.width();
    *height = image.height();
    return 1;
}

// The picture at `path` scaled to fit `side` x `side`, as RGBA bytes into
// `out` (room for `cap`), its size in `width` / `height`. Whether it could
// be read.
extern "C" bool ost_image_rgba(const char *path, int side, unsigned char *out, size_t cap, int *width, int *height)
{
    QImage image(QString::fromUtf8(path));
    if (image.isNull())
        return false;
    image = image.scaled(side, side, Qt::KeepAspectRatio, Qt::SmoothTransformation).convertToFormat(QImage::Format_RGBA8888);
    const size_t need = size_t(image.width()) * size_t(image.height()) * 4;
    if (need > cap)
        return false;
    for (int y = 0; y < image.height(); ++y)
        memcpy(out + size_t(y) * size_t(image.width()) * 4, image.constScanLine(y), size_t(image.width()) * 4);
    *width = image.width();
    *height = image.height();
    return true;
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

// A translation language ("de", "fr-ca", "sr-latn") as Teams lists it under
// Settings ▸ General ▸ Translation: its usual locale named in itself and in
// English, as "Deutsch (Deutschland)\tGerman (Germany)". 0 (nothing
// written) when the locale data doesn't know the language.
extern "C" size_t ost_language_display(const char *code, char *out, size_t cap)
{
    const QString c = QString::fromUtf8(code);
    const QStringList parts = c.split(QLatin1Char('-'));
    // A second part must be a script or a region (not "chs").
    if (parts.size() > 2 || (parts.size() == 2 && parts[1].size() != 2 && parts[1].size() != 4))
        return 0;
    const QLocale loc(c);
    if (loc.language() == QLocale::C || loc.language() == QLocale::AnyLanguage)
        return 0;
    if (QLocale::languageToCode(loc.language()) != parts[0].toLower())
        return 0;
    // The language's plain name: the locale's own may be a dialect's
    // ("American English", "français canadien"); the plain one is the
    // shortest of the language's locale names inside it ("English",
    // "français"), never another dialect ("Vlaams" for Nederlands).
    const QString own = loc.nativeLanguageName();
    QString native = own;
    for (const QLocale &l : QLocale::matchingLocales(loc.language(), loc.script(), QLocale::AnyTerritory)) {
        const QString n = l.nativeLanguageName();
        if (!n.isEmpty() && n.size() < native.size() && own.contains(n, Qt::CaseInsensitive))
            native = n;
    }
    if (!native.isEmpty())
        native[0] = native[0].toUpper();
    const QString nativeRegion = loc.nativeTerritoryName();
    const QString english = QLocale::languageToString(loc.language());
    const QString region = QLocale::territoryToString(loc.territory());
    if (native.isEmpty() || english.isEmpty())
        return 0;
    const QString text = native + (nativeRegion.isEmpty() ? QString() : QStringLiteral(" (") + nativeRegion + QLatin1Char(')'))
        + QLatin1Char('\t') + english + (region.isEmpty() ? QString() : QStringLiteral(" (") + region + QLatin1Char(')'));
    const QByteArray b = text.toUtf8();
    if (size_t(b.size()) >= cap)
        return 0;
    memcpy(out, b.constData(), size_t(b.size()));
    return size_t(b.size());
}

// Quit the application (Teams' Save and restart: main.rs starts OST again).
extern "C" void ost_quit_application()
{
    QGuiApplication::quit();
}

#include <QtCore/QMargins>
#include <QtGui/QScreen>
#include <dlfcn.h>

// Teams' notification banners (its "custom notifications" window, measured
// on winpc 2026-11-15): a 372-wide window flush with the screen's left or
// right edge and 90 px from the top or bottom of its work area, in the
// corner Settings ▸ Notifications ▸ Position on the screen picks. On X11
// OST moves its banner window there. A Wayland client can't place its own
// windows; there the window becomes a wlr-layer-shell surface anchored to
// that corner, through KDE's LayerShellQt when it is installed (its 6.x
// library, loaded at run time, so OST doesn't need it to build or run).
namespace {
struct LayerShell {
    void *(*get)(QWindow *);
    void (*setAnchors)(void *, int);
    void (*setMargins)(void *, const QMargins &);
    void (*setLayer)(void *, int);
    void (*setKeyboardInteractivity)(void *, int);
    void (*setActivateOnShow)(void *, bool);
    void (*setScope)(void *, const QString &);
};

const LayerShell *layer_shell()
{
    static LayerShell ls {};
    static const bool ok = [] {
        void *lib = dlopen("libLayerShellQtInterface.so.6", RTLD_NOW | RTLD_GLOBAL);
        if (!lib)
            return false;
        auto sym = [lib](const char *name) { return dlsym(lib, name); };
        ls.get = reinterpret_cast<void *(*)(QWindow *)>(sym("_ZN12LayerShellQt6Window3getEP7QWindow"));
        ls.setAnchors = reinterpret_cast<void (*)(void *, int)>(sym("_ZN12LayerShellQt6Window10setAnchorsE6QFlagsINS0_6AnchorEE"));
        ls.setMargins = reinterpret_cast<void (*)(void *, const QMargins &)>(sym("_ZN12LayerShellQt6Window10setMarginsERK8QMargins"));
        ls.setLayer = reinterpret_cast<void (*)(void *, int)>(sym("_ZN12LayerShellQt6Window8setLayerENS0_5LayerE"));
        ls.setKeyboardInteractivity = reinterpret_cast<void (*)(void *, int)>(sym("_ZN12LayerShellQt6Window24setKeyboardInteractivityENS0_21KeyboardInteractivityE"));
        ls.setActivateOnShow = reinterpret_cast<void (*)(void *, bool)>(sym("_ZN12LayerShellQt6Window17setActivateOnShowEb"));
        ls.setScope = reinterpret_cast<void (*)(void *, const QString &)>(sym("_ZN12LayerShellQt6Window8setScopeERK7QString"));
        return ls.get && ls.setAnchors && ls.setMargins && ls.setLayer && ls.setKeyboardInteractivity && ls.setActivateOnShow && ls.setScope;
    }();
    return ok ? &ls : nullptr;
}

QWindow *window_titled(const char *title)
{
    const QString t = QString::fromUtf8(title);
    for (QWindow *w : QGuiApplication::allWindows())
        if (w->title() == t)
            return w;
    return nullptr;
}

// GNOME's compositor has no layer shell.
bool gnome_family()
{
    const QByteArray d = qgetenv("XDG_CURRENT_DESKTOP").toLower();
    return d.contains("gnome") || d.contains("unity") || d.contains("pantheon");
}
}

// How OST can place its banner window: 2 on X11 (it moves it), 1 on
// Wayland with a layer shell, 0 where it can't (then the desktop's own
// notifications are used).
extern "C" int ost_banner_support()
{
    const QString p = QGuiApplication::platformName();
    if (p == QLatin1String("xcb"))
        return 2;
    if (p.startsWith(QLatin1String("wayland")) && !gnome_family() && layer_shell())
        return 1;
    return 0;
}

// Ready the window titled `title` before it is first shown: it appears
// without taking focus; on Wayland it becomes a layer-shell surface above
// windows that takes the keyboard only when clicked (the quick reply).
extern "C" bool ost_banner_prepare(const char *title)
{
    QWindow *w = window_titled(title);
    if (!w || w->isVisible())
        return false;
    // X11: appear without taking focus from the window you're in.
    w->setProperty("_q_showWithoutActivating", true);
    const LayerShell *ls = layer_shell();
    if (!ls || !QGuiApplication::platformName().startsWith(QLatin1String("wayland")))
        return false;
    void *s = ls->get(w);
    if (!s)
        return false;
    ls->setLayer(s, 2);                     // LayerTop
    ls->setKeyboardInteractivity(s, 2);     // KeyboardInteractivityOnDemand
    ls->setActivateOnShow(s, false);
    ls->setScope(s, QStringLiteral("ost-notifications"));
    return true;
}

// Put the window titled `title` in `corner` ("BR", "TR", "BL", "TL"),
// `margin` px from the top or bottom of the work area.
extern "C" void ost_banner_place(const char *title, const char *corner, int margin)
{
    QWindow *w = window_titled(title);
    if (!w)
        return;
    const QByteArray c(corner);
    const bool top = c.startsWith('T'), left = c.endsWith('L');
    if (QGuiApplication::platformName() == QLatin1String("xcb")) {
        QScreen *screen = w->screen() ? w->screen() : QGuiApplication::primaryScreen();
        const QRect area = screen->availableGeometry();
        const int x = left ? area.left() : area.right() + 1 - w->width();
        const int y = top ? area.top() + margin : area.bottom() + 1 - margin - w->height();
        w->setPosition(x, y);
        return;
    }
    const LayerShell *ls = layer_shell();
    if (!ls)
        return;
    void *s = ls->get(w);
    // Anchors: top 1, bottom 2, left 4, right 8.
    ls->setAnchors(s, (top ? 1 : 2) | (left ? 4 : 8));
    ls->setMargins(s, QMargins(0, top ? margin : 0, 0, top ? 0 : margin));
}

// Teams' Sharing control bar: centred at the top of the screen (8 px down,
// 5 minimized) or where it was dragged. On Wayland it becomes a layer-shell
// surface above windows (an app can't place its own windows there); on
// X11 the QML window places itself.
extern "C" bool ost_toolbar_prepare(const char *title)
{
    QWindow *w = window_titled(title);
    if (!w || w->isVisible())
        return false;
    w->setProperty("_q_showWithoutActivating", true);
    const LayerShell *ls = layer_shell();
    if (!ls || !QGuiApplication::platformName().startsWith(QLatin1String("wayland")))
        return false;
    void *s = ls->get(w);
    if (!s)
        return false;
    ls->setLayer(s, 3);                     // LayerOverlay: over full-screen windows too
    ls->setKeyboardInteractivity(s, 2);     // OnDemand: its menus' search takes keys when clicked
    ls->setActivateOnShow(s, false);
    ls->setScope(s, QStringLiteral("ost-sharing-control-bar"));
    ls->setAnchors(s, 1);                   // top, centred
    return true;
}

// `x` < 0: centred; else that far from the screen's left. `y` from its top.
extern "C" void ost_toolbar_place(const char *title, int x, int y)
{
    QWindow *w = window_titled(title);
    const LayerShell *ls = layer_shell();
    if (!w || !ls)
        return;
    void *s = ls->get(w);
    if (!s)
        return;
    ls->setAnchors(s, x < 0 ? 1 : (1 | 4));
    ls->setMargins(s, QMargins(x < 0 ? 0 : x, y, 0, 0));
}

#include <QtQuick/QQuickItem>
#include <QtQuick/QQuickWindow>

// WindowTool (src/window_tool.rs): the window a QML item is in.
namespace {
QWindow *item_window(void *item)
{
    auto *it = static_cast<QQuickItem *>(item);
    return it ? it->window() : nullptr;
}
}

// Whether the desktop shows the item's window. On Wayland this is the only
// sign of a minimize (see window_tool.rs): Qt stops treating the window as
// exposed when the compositor suspends it or stops its frame callbacks.
extern "C" bool ost_item_window_exposed(void *item)
{
    QWindow *w = item_window(item);
    return w && w->isVisible() && w->isExposed();
}

// Before the item's window first shows: a layer-shell surface on `layer`
// (2 top, 3 overlay) that takes the keyboard only when clicked and doesn't
// take focus when it appears. False without a layer shell (X11, GNOME):
// the window is left as it is.
extern "C" bool ost_item_layer_prepare(void *item, const char *scope, int layer)
{
    QWindow *w = item_window(item);
    if (!w || w->isVisible())
        return false;
    if (!QGuiApplication::platformName().startsWith(QLatin1String("wayland")) || gnome_family())
        return false;
    const LayerShell *ls = layer_shell();
    if (!ls)
        return false;
    void *s = ls->get(w);
    if (!s)
        return false;
    ls->setLayer(s, layer == 3 ? 3 : 2);
    ls->setKeyboardInteractivity(s, 2);     // KeyboardInteractivityOnDemand
    ls->setActivateOnShow(s, false);
    ls->setScope(s, QString::fromUtf8(scope ? scope : "ost"));
    w->setProperty("_ost_layer", true);
    return true;
}

// Anchor the item's layer-shell window: `anchors` top 1, bottom 2, left 4,
// right 8; the margins from those edges of the work area.
extern "C" void ost_item_layer_place(void *item, int anchors, int left, int top, int right, int bottom)
{
    QWindow *w = item_window(item);
    const LayerShell *ls = layer_shell();
    if (!w || !ls || !w->property("_ost_layer").toBool())
        return;
    void *s = ls->get(w);
    if (!s)
        return;
    ls->setAnchors(s, anchors);
    ls->setMargins(s, QMargins(left, top, right, bottom));
}

#include <QtGui/QRegion>

// Annotate's window (Teams' annotation entity: transparent, frameless,
// always on top, the whole screen): on Wayland a layer-shell surface on
// the overlay layer anchored to every edge, which takes the keyboard only
// when clicked.
extern "C" bool ost_overlay_prepare(const char *title)
{
    QWindow *w = window_titled(title);
    if (!w || w->isVisible())
        return false;
    w->setProperty("_q_showWithoutActivating", true);
    const LayerShell *ls = layer_shell();
    if (!ls || !QGuiApplication::platformName().startsWith(QLatin1String("wayland")))
        return false;
    void *s = ls->get(w);
    if (!s)
        return false;
    ls->setLayer(s, 3);                     // LayerOverlay
    ls->setKeyboardInteractivity(s, 2);     // KeyboardInteractivityOnDemand
    ls->setActivateOnShow(s, false);
    ls->setScope(s, QStringLiteral("ost-annotation"));
    ls->setAnchors(s, 1 | 2 | 4 | 8);
    ls->setMargins(s, QMargins());
    return true;
}

// Where the window titled `title` takes the pointer: only (x, y, w, h), or
// everywhere when w or h is 0 (Whiteboard's click-through mode).
extern "C" void ost_window_input_region(const char *title, int x, int y, int w, int h)
{
    QWindow *win = window_titled(title);
    if (!win)
        return;
    win->setMask(w > 0 && h > 0 ? QRegion(x, y, w, h) : QRegion());
}

// For development: with OST_QML_DIR set (a checkout's desktop/qml), QML
// files load from there instead of the compiled-in module, so a QML change
// can be tried without rebuilding. Assets and shaders resolve beside them.
#include <QtCore/QFile>
#include <QtQml/QQmlAbstractUrlInterceptor>
#include <QtQml/QQmlEngine>

namespace {
class QmlDirInterceptor : public QQmlAbstractUrlInterceptor
{
public:
    explicit QmlDirInterceptor(const QString &dir) : m_dir(dir) {}
    QUrl intercept(const QUrl &url, DataType type) override
    {
        if (type != QmlFile && type != JavaScriptFile)
            return url;
        static const QString prefix = QStringLiteral("qrc:/qt/qml/com/ost/desktop/qml/");
        const QString s = url.toString();
        if (!s.startsWith(prefix))
            return url;
        const QString file = m_dir + QLatin1Char('/') + s.mid(prefix.size());
        return QFile::exists(file) ? QUrl::fromLocalFile(file) : url;
    }

private:
    QString m_dir;
};
} // namespace

extern "C" void ost_dev_qml_dir(void *engine, const char *dir)
{
    if (!engine || !dir || !*dir)
        return;
    static_cast<QQmlEngine *>(engine)->addUrlInterceptor(new QmlDirInterceptor(QString::fromUtf8(dir)));
}

// FluentIcon's pictures ("image://fluent/<name>?c=<colour>&s=<from>,<to>;…"):
// a bundled single-colour Fluent SVG with its #212121 (or currentColor)
// swapped for the wanted colour, then any other colour swaps (a folder's
// colour), drawn here as the item is made. A data: URL would load in the
// background and leave the icon blank for a frame or more (the app bar's
// Chat and Calendar after start), where Teams shows its icons at once.
// Swapping the colour in the SVG text keeps the picture the same on GPU,
// software and offscreen backends.
#include <QtCore/QBuffer>
#include <QtCore/QHash>
#include <QtCore/QMutex>
#include <QtCore/QUrlQuery>
#include <QtQuick/QQuickImageProvider>

namespace {
class FluentIconProvider : public QQuickImageProvider
{
public:
    FluentIconProvider() : QQuickImageProvider(QQuickImageProvider::Image) {}

    QImage requestImage(const QString &id, QSize *size, const QSize &requestedSize) override
    {
        const qsizetype q = id.indexOf(QLatin1Char('?'));
        const QUrlQuery query(q < 0 ? QString() : id.mid(q + 1));
        QByteArray svg = text(q < 0 ? id : id.left(q));
        if (svg.isEmpty()) {
            if (size)
                *size = QSize();
            return QImage();
        }
        const QByteArray colour = query.queryItemValue(QStringLiteral("c"), QUrl::FullyDecoded).toUtf8();
        if (!colour.isEmpty()) {
            svg.replace("#212121", colour);
            svg.replace("currentColor", colour);
        }
        const QString swaps = query.queryItemValue(QStringLiteral("s"), QUrl::FullyDecoded);
        for (const QString &pair : swaps.split(QLatin1Char(';'), Qt::SkipEmptyParts)) {
            const QStringList p = pair.split(QLatin1Char(','));
            if (p.size() == 2)
                svg.replace(p[0].toUtf8(), p[1].toUtf8());
        }
        QBuffer buffer(&svg);
        buffer.open(QIODevice::ReadOnly);
        QImageReader reader(&buffer, "svg");
        if (requestedSize.width() > 0 && requestedSize.height() > 0)
            reader.setScaledSize(requestedSize);
        const QImage image = reader.read();
        if (size)
            *size = image.size();
        return image;
    }

private:
    // Each icon's SVG text, read from the bundle once.
    QByteArray text(const QString &name)
    {
        QMutexLocker lock(&m_lock);
        const auto it = m_files.constFind(name);
        if (it != m_files.constEnd())
            return *it;
        QFile file(QStringLiteral(":/qt/qml/com/ost/desktop/assets/icons/") + name + QStringLiteral(".svg"));
        const QByteArray t = file.open(QIODevice::ReadOnly) ? file.readAll() : QByteArray();
        if (t.isEmpty())
            qWarning("icon failed: %s", qPrintable(name));
        m_files.insert(name, t);
        return t;
    }

    QMutex m_lock;
    QHash<QString, QByteArray> m_files;
};
} // namespace

extern "C" void ost_add_icon_provider(void *engine)
{
    if (engine)
        static_cast<QQmlEngine *>(engine)->addImageProvider(QStringLiteral("fluent"), new FluentIconProvider);
}

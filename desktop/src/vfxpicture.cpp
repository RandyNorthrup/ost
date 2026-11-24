// Adding your own video background, as Teams desktop's Add new does: the
// picture must be an image at least 360 px on each side and no more than
// four times as wide as it is tall. It is kept as a JPEG, with a 280 px
// wide JPEG thumbnail for its tile (Teams' <uuid>.jpeg and
// <uuid>_thumb.jpeg). src/video_effects.rs names and lists them.
#include <QtGui/QImage>
#include <QtGui/QImageReader>

// 0 added; 1 not an image; 2 the wrong size; 3 couldn't be written.
extern "C" int ost_vfx_import_picture(const char *src, const char *dst, const char *thumb)
{
    QImageReader reader(QString::fromUtf8(src));
    reader.setAutoTransform(true);
    QImage img = reader.read();
    if (img.isNull())
        return 1;
    const int w = img.width(), h = img.height();
    if (w < 360 || h < 360 || double(w) / double(h) > 4.0)
        return 2;
    // A JPEG has no transparency: what was see-through becomes white.
    if (img.hasAlphaChannel()) {
        QImage flat(img.size(), QImage::Format_RGB32);
        flat.fill(Qt::white);
        QImage src32 = img.convertToFormat(QImage::Format_ARGB32_Premultiplied);
        for (int y = 0; y < flat.height(); ++y) {
            auto *d = reinterpret_cast<QRgb *>(flat.scanLine(y));
            const auto *s = reinterpret_cast<const QRgb *>(src32.constScanLine(y));
            for (int x = 0; x < flat.width(); ++x) {
                const int a = qAlpha(s[x]);
                d[x] = qRgb(qRed(s[x]) + (255 - a), qGreen(s[x]) + (255 - a), qBlue(s[x]) + (255 - a));
            }
        }
        img = flat;
    }
    if (!img.save(QString::fromUtf8(dst), "JPEG", 90))
        return 3;
    QImage small = img.scaledToWidth(280, Qt::SmoothTransformation);
    if (!small.save(QString::fromUtf8(thumb), "JPEG", 90))
        return 3;
    return 0;
}

// Outlook's Graphics pane inserts a stock image as its picture drawn on a
// canvas and taken as a JPEG at quality 0.5, at the picture's own size
// (canvas.toDataURL("image/jpeg", 0.5); captured 2026-11-24). 0 written
// (its size in w and h); 1 not an image; 3 couldn't be written.
extern "C" int ost_picture_to_jpeg(const char *src, const char *dst, int quality, int *w, int *h)
{
    QImageReader reader(QString::fromUtf8(src));
    QImage img = reader.read();
    if (img.isNull())
        return 1;
    // A canvas starts transparent black, and JPEG keeps what was drawn.
    if (img.hasAlphaChannel()) {
        QImage flat(img.size(), QImage::Format_RGB32);
        flat.fill(Qt::black);
        QImage src32 = img.convertToFormat(QImage::Format_ARGB32_Premultiplied);
        for (int y = 0; y < flat.height(); ++y) {
            auto *d = reinterpret_cast<QRgb *>(flat.scanLine(y));
            const auto *s = reinterpret_cast<const QRgb *>(src32.constScanLine(y));
            for (int x = 0; x < flat.width(); ++x)
                d[x] = qRgb(qRed(s[x]), qGreen(s[x]), qBlue(s[x]));
        }
        img = flat;
    }
    *w = img.width();
    *h = img.height();
    return img.save(QString::fromUtf8(dst), "JPEG", quality) ? 0 : 3;
}

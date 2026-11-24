// The clip recorder's person mask (src/clip_mask.rs) takes the camera's
// frames from its QML video sink: whenever the segmentation model is free,
// the newest frame is shrunk to the model's 192 x 192 RGB and handed over.
#include <QtCore/QByteArray>
#include <QtCore/QHash>
#include <QtCore/QPointer>
#include <QtGui/QImage>
#include <QtMultimedia/QVideoFrame>
#include <QtMultimedia/QVideoSink>
#include <QtQuick/QQuickItem>
#include <cstring>

extern "C" bool ost_clip_mask_wants(void *item);
extern "C" void ost_clip_mask_frame(void *item, const unsigned char *rgb, int side);

namespace {
constexpr int Side = 192;

QHash<void *, QMetaObject::Connection> &connections()
{
    static QHash<void *, QMetaObject::Connection> map;
    return map;
}
} // namespace

extern "C" void ost_clip_mask_attach(void *item, void *sink)
{
    auto *owner = static_cast<QQuickItem *>(item);
    if (!owner)
        return;
    if (connections().contains(item))
        QObject::disconnect(connections().take(item));
    auto *s = qobject_cast<QVideoSink *>(static_cast<QObject *>(sink));
    if (!s)
        return;
    // The item is the connection's context: it ends when the item goes.
    connections().insert(item, QObject::connect(s, &QVideoSink::videoFrameChanged, owner, [item](const QVideoFrame &frame) {
        if (!frame.isValid() || !ost_clip_mask_wants(item))
            return;
        QImage img = frame.toImage();
        if (img.isNull())
            return;
        img = img.scaled(Side, Side, Qt::IgnoreAspectRatio, Qt::SmoothTransformation).convertToFormat(QImage::Format_RGB888);
        QByteArray rgb(Side * Side * 3, Qt::Uninitialized);
        for (int y = 0; y < Side; ++y)
            std::memcpy(rgb.data() + y * Side * 3, img.constScanLine(y), Side * 3);
        ost_clip_mask_frame(item, reinterpret_cast<const unsigned char *>(rgb.constData()), Side);
    }));
    QObject::connect(owner, &QObject::destroyed, [item]() { connections().remove(item); });
}

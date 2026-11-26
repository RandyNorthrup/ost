// CameraFeed's pictures (src/camera_feed.rs) for Qt: handed to a QML
// video sink, and saved as a photo.
#include <QtCore/QObject>
#include <QtCore/QString>
#include <QtGui/QImage>
#include <QtMultimedia/QVideoFrame>
#include <QtMultimedia/QVideoSink>

extern "C" bool ost_camera_feed_show(void *sink, const unsigned char *rgba, int width, int height)
{
    auto *s = qobject_cast<QVideoSink *>(static_cast<QObject *>(sink));
    if (!s)
        return false;
    if (!rgba || width <= 0 || height <= 0) {
        s->setVideoFrame(QVideoFrame());
        return true;
    }
    // (copy(): the frame keeps its own pixels.)
    const QImage image = QImage(rgba, width, height, width * 4, QImage::Format_RGBA8888).copy();
    s->setVideoFrame(QVideoFrame(image));
    return true;
}

extern "C" bool ost_camera_feed_save(const unsigned char *rgba, int width, int height, const char *path)
{
    if (!rgba || width <= 0 || height <= 0 || !path)
        return false;
    const QImage image(rgba, width, height, width * 4, QImage::Format_RGBA8888);
    return image.convertToFormat(QImage::Format_RGB888).save(QString::fromUtf8(path), "JPG", 92);
}

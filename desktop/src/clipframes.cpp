// Recording a video clip as Teams' recorder does: what the recorder's
// picture shows (the camera, the screen, the microphone picture, and later
// backdrops, effects and drawings) is what gets recorded. The helper item
// (ClipFrames, src/clip_frames.rs) sits inside that picture; it grabs its
// parent 30 times a second at the clip's size and feeds the frames, with
// the chosen microphone, to a QMediaRecorder writing an H.264/AAC MP4.
// Grabbing is slower than 30 frames a second and Qt's encoder times frames
// by their count, so the newest picture is sent on every tick and the
// picture itself is refreshed as often as it can be grabbed.
#include <QtCore/QElapsedTimer>
#include <QtCore/QHash>
#include <QtCore/QPointer>
#include <QtCore/QTimer>
#include <QtCore/QUrl>
#include <QtGui/QImage>
#include <QtMultimedia/QAudioDevice>
#include <QtMultimedia/QAudioInput>
#include <QtMultimedia/QMediaCaptureSession>
#include <QtMultimedia/QMediaDevices>
#include <QtMultimedia/QMediaFormat>
#include <QtMultimedia/QMediaRecorder>
#include <QtMultimedia/QVideoFrame>
#include <QtMultimedia/QVideoFrameFormat>
#include <QtMultimedia/QVideoFrameInput>
#include <QtQuick/QQuickItem>
#include <QtQuick/QQuickItemGrabResult>

extern "C" void ost_clip_frames_recorded(void *helper, long long ms);
extern "C" void ost_clip_frames_stopped(void *helper, const char *path);
extern "C" void ost_clip_frames_failed(void *helper, const char *message);

namespace {

struct ClipRecording {
    QMediaCaptureSession session;
    QMediaRecorder recorder;
    QAudioInput *audio = nullptr;
    QVideoFrameInput *frames = nullptr;
    QTimer ticker;
    QPointer<QQuickItem> source;
    QSharedPointer<QQuickItemGrabResult> pending;
    QSize size;
    bool paused = false;
    bool ready = true;
    // The recording's own clock (paused time left out), which stamps each
    // frame: frames come as fast as the picture can be grabbed, so their
    // times can't be counted from a frame rate.
    QElapsedTimer clock;
    qint64 before = 0;
    qint64 last = -1;
    qint64 now() const { return before + (clock.isValid() ? clock.nsecsElapsed() / 1000 : 0); }
    QImage latest;

    ~ClipRecording()
    {
        ticker.stop();
        session.setRecorder(nullptr);
        session.setVideoFrameInput(nullptr);
        session.setAudioInput(nullptr);
        delete frames;
        delete audio;
    }
};

QHash<void *, ClipRecording *> &recordings()
{
    static QHash<void *, ClipRecording *> map;
    return map;
}

void grab(ClipRecording *r)
{
    if (r->paused || r->pending || !r->source || !r->source->window())
        return;
    QSharedPointer<QQuickItemGrabResult> res = r->source->grabToImage(r->size);
    if (!res)
        return;
    r->pending = res;
    QObject::connect(res.data(), &QQuickItemGrabResult::ready, &r->ticker, [r]() {
        if (!r->pending)
            return;
        QImage img = r->pending->image();
        r->pending.reset();
        if (img.isNull() || r->paused)
            return;
        if (img.size() != r->size)
            img = img.scaled(r->size, Qt::IgnoreAspectRatio, Qt::SmoothTransformation);
        r->latest = img.convertToFormat(QImage::Format_RGBA8888);
    });
}

// One tick: the newest picture goes to the encoder (when it has room), and
// a fresh grab starts if none is under way.
void tick(ClipRecording *r)
{
    grab(r);
    if (r->paused || r->latest.isNull())
        return;
    // A frame of its own each time (the encoder keeps frames it is given).
    QVideoFrame frame(r->latest.copy());
    qint64 t = r->now();
    if (t <= r->last)
        t = r->last + 1;
    frame.setStartTime(t);
    frame.setEndTime(t + 33333);
    r->last = t;
    // Without room in the encoder's queue this tick's frame is dropped.
    r->ready = r->frames->sendVideoFrame(frame);
}

} // namespace

// Get ready to record `helper`'s parent item at `width` x `height` with the
// microphone `mic_id` (empty: the default), muted unless `mic_on`. The
// session, its microphone and recorder are set up ahead of recording:
// Qt's encoder starts only once audio flows, and a microphone opened at
// the moment recording starts would cost the clip's first seconds.
extern "C" bool ost_clip_frames_prepare(void *helper, const char *mic_id, bool mic_on, int width, int height)
{
    auto *item = static_cast<QQuickItem *>(helper);
    if (!item || !item->parentItem())
        return false;
    if (auto *old = recordings().take(helper))
        delete old;
    auto *r = new ClipRecording;
    r->source = item->parentItem();
    r->size = QSize(width > 0 ? width : 1280, height > 0 ? height : 720);
    QVideoFrameFormat format(r->size, QVideoFrameFormat::Format_RGBA8888);
    r->frames = new QVideoFrameInput(format);
    r->session.setVideoFrameInput(r->frames);
    // A microphone always goes in, muted when it's off: the MP4 muxer
    // waits for an audio track to interleave, and stalls without one.
    r->audio = new QAudioInput;
    r->audio->setMuted(!mic_on);
    const QByteArray want(mic_id ? mic_id : "");
    if (!want.isEmpty()) {
        const auto inputs = QMediaDevices::audioInputs();
        for (const QAudioDevice &d : inputs) {
            if (d.id() == want) {
                r->audio->setDevice(d);
                break;
            }
        }
    }
    r->session.setAudioInput(r->audio);
    QMediaFormat mf(QMediaFormat::MPEG4);
    mf.setVideoCodec(QMediaFormat::VideoCodec::H264);
    mf.setAudioCodec(QMediaFormat::AudioCodec::AAC);
    r->recorder.setMediaFormat(mf);
    r->recorder.setVideoResolution(r->size);
    r->recorder.setQuality(QMediaRecorder::HighQuality);
    r->session.setRecorder(&r->recorder);
    QObject::connect(&r->recorder, &QMediaRecorder::durationChanged, &r->ticker, [helper](qint64 ms) {
        ost_clip_frames_recorded(helper, ms);
    });
    QObject::connect(&r->recorder, &QMediaRecorder::recorderStateChanged, &r->ticker, [helper, r](QMediaRecorder::RecorderState s) {
        if (s != QMediaRecorder::StoppedState)
            return;
        const QByteArray file = r->recorder.actualLocation().toLocalFile().toUtf8();
        ost_clip_frames_stopped(helper, file.constData());
    });
    QObject::connect(&r->recorder, &QMediaRecorder::errorOccurred, &r->ticker, [helper](QMediaRecorder::Error, const QString &text) {
        const QByteArray msg = text.toUtf8();
        ost_clip_frames_failed(helper, msg.constData());
    });
    QObject::connect(&r->ticker, &QTimer::timeout, &r->ticker, [r]() { tick(r); });
    r->ticker.setTimerType(Qt::PreciseTimer);
    r->ticker.setInterval(33);
    r->paused = true;
    recordings().insert(helper, r);
    return true;
}

// Start recording to `path` (after prepare).
extern "C" bool ost_clip_frames_start(void *helper, const char *path)
{
    auto *r = recordings().value(helper);
    if (!r)
        return false;
    r->recorder.setOutputLocation(QUrl::fromLocalFile(QString::fromUtf8(path)));
    r->paused = false;
    r->before = 0;
    r->last = -1;
    r->clock.start();
    grab(r);
    r->recorder.record();
    r->ticker.start();
    // Qt 6.10's video encoder for frame inputs stays paused after record()
    // until the recording is paused and resumed once (seen on linuxlt:
    // without this only frames after a resume were encoded).
    QTimer::singleShot(150, &r->ticker, [r]() {
        if (r->paused || r->recorder.recorderState() != QMediaRecorder::RecordingState)
            return;
        r->recorder.pause();
        r->recorder.record();
    });
    return true;
}

extern "C" void ost_clip_frames_pause(void *helper)
{
    if (auto *r = recordings().value(helper)) {
        r->paused = true;
        r->before = r->now();
        r->clock.invalidate();
        r->recorder.pause();
    }
}

extern "C" void ost_clip_frames_resume(void *helper)
{
    if (auto *r = recordings().value(helper)) {
        r->paused = false;
        r->clock.start();
        r->recorder.record();
    }
}

// Stop: the file is finished when ost_clip_frames_stopped is called.
extern "C" void ost_clip_frames_stop(void *helper)
{
    if (auto *r = recordings().value(helper)) {
        r->ticker.stop();
        r->paused = true;
        r->recorder.stop();
    }
}

// Forget the recording (after it stopped, or when the item goes).
extern "C" void ost_clip_frames_release(void *helper)
{
    if (auto *r = recordings().take(helper))
        delete r;
}

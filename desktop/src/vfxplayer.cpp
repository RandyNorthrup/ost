// Teams' video backgrounds as camera-sized pictures: a background (a JPEG
// or PNG picture, or one of Teams' animated MP4s) is opened with FFmpeg and
// each of its frames is scaled to cover the camera's frame (centred, the
// overflow cropped, as Teams fills your video) and handed over as I420.
// Animated backgrounds loop. src/video_effects.rs drives it and gives the
// frames to the effects engine (ost-vfx).
extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/imgutils.h>
#include <libswscale/swscale.h>
}


namespace {

struct Player {
    AVFormatContext *fmt = nullptr;
    AVCodecContext *dec = nullptr;
    SwsContext *sws = nullptr;
    AVPacket *pkt = nullptr;
    AVFrame *frame = nullptr;
    int stream = -1;
    int w = 0, h = 0;
    double fps = 0;
    // The scaler's source crop (what of the picture covers the frame).
    int sw = 0, sh = 0, sfmt = -1;

    ~Player()
    {
        sws_freeContext(sws);
        av_frame_free(&frame);
        av_packet_free(&pkt);
        avcodec_free_context(&dec);
        avformat_close_input(&fmt);
    }
};

// The next decoded frame (looping at the end), or false.
bool decode(Player *p)
{
    for (int tries = 0; tries < 2; ++tries) {
        while (true) {
            int r = avcodec_receive_frame(p->dec, p->frame);
            if (r == 0)
                return true;
            if (r == AVERROR_EOF)
                break;
            if (r != AVERROR(EAGAIN))
                return false;
            r = av_read_frame(p->fmt, p->pkt);
            if (r < 0) {
                avcodec_send_packet(p->dec, nullptr);
                continue;
            }
            if (p->pkt->stream_index == p->stream)
                avcodec_send_packet(p->dec, p->pkt);
            av_packet_unref(p->pkt);
        }
        // The end: back to the start.
        if (av_seek_frame(p->fmt, p->stream, 0, AVSEEK_FLAG_BACKWARD) < 0)
            return false;
        avcodec_flush_buffers(p->dec);
    }
    return false;
}

} // namespace

// Open `path` to be played at `width` x `height`. Null if it can't be read.
extern "C" void *ost_vfx_player_open(const char *path, int width, int height)
{
    auto *p = new Player;
    p->w = width & ~1;
    p->h = height & ~1;
    if (avformat_open_input(&p->fmt, path, nullptr, nullptr) < 0 || avformat_find_stream_info(p->fmt, nullptr) < 0) {
        delete p;
        return nullptr;
    }
    const AVCodec *codec = nullptr;
    p->stream = av_find_best_stream(p->fmt, AVMEDIA_TYPE_VIDEO, -1, -1, &codec, 0);
    if (p->stream < 0 || !codec) {
        delete p;
        return nullptr;
    }
    AVStream *st = p->fmt->streams[p->stream];
    p->dec = avcodec_alloc_context3(codec);
    avcodec_parameters_to_context(p->dec, st->codecpar);
    if (avcodec_open2(p->dec, codec, nullptr) < 0) {
        delete p;
        return nullptr;
    }
    AVRational r = st->avg_frame_rate.num ? st->avg_frame_rate : st->r_frame_rate;
    p->fps = r.num && r.den ? av_q2d(r) : 0;
    p->pkt = av_packet_alloc();
    p->frame = av_frame_alloc();
    return p;
}

// Frames a second (0 for a still picture).
extern "C" double ost_vfx_player_fps(void *player)
{
    auto *p = static_cast<Player *>(player);
    if (!p)
        return 0;
    switch (p->dec->codec_id) {
    case AV_CODEC_ID_MJPEG:
    case AV_CODEC_ID_PNG:
    case AV_CODEC_ID_BMP:
    case AV_CODEC_ID_WEBP:
        return 0;
    default:
        return p->fps > 0 ? p->fps : 30;
    }
}

// The next frame, scaled to cover the size and written to `out` as I420
// (width x height x 3/2 bytes). Returns false when nothing could be read.
extern "C" bool ost_vfx_player_next(void *player, unsigned char *out)
{
    auto *p = static_cast<Player *>(player);
    if (!p || !decode(p))
        return false;
    AVFrame *f = p->frame;
    // The part of the picture with the frame's shape, centred.
    int cw = f->width, ch = f->height;
    if ((long long)cw * p->h > (long long)ch * p->w)
        cw = (int)((long long)ch * p->w / p->h);
    else
        ch = (int)((long long)cw * p->h / p->w);
    cw &= ~1;
    ch &= ~1;
    int cx = ((f->width - cw) / 2) & ~1, cy = ((f->height - ch) / 2) & ~1;
    if (!p->sws || p->sw != cw || p->sh != ch || p->sfmt != f->format) {
        sws_freeContext(p->sws);
        p->sws = sws_getContext(cw, ch, (AVPixelFormat)f->format, p->w, p->h, AV_PIX_FMT_YUV420P, SWS_BICUBIC, nullptr, nullptr, nullptr);
        p->sw = cw;
        p->sh = ch;
        p->sfmt = f->format;
        if (!p->sws)
            return false;
    }
    // The crop: each plane's pointer moved to the crop's corner.
    const AVPixFmtDescriptor *d = av_pix_fmt_desc_get((AVPixelFormat)f->format);
    const uint8_t *src[4] = {nullptr, nullptr, nullptr, nullptr};
    for (int i = 0; i < 4 && f->data[i]; ++i) {
        // Bytes from one pixel to the next on this plane (its first
        // component's step), and whether the plane is subsampled.
        int step = 1;
        bool chroma = false;
        for (int c = 0; c < d->nb_components; ++c) {
            if (d->comp[c].plane == i) {
                step = d->comp[c].step;
                chroma = !(d->flags & AV_PIX_FMT_FLAG_RGB) && (c == 1 || c == 2);
                break;
            }
        }
        int sx = chroma ? cx >> d->log2_chroma_w : cx;
        int sy = chroma ? cy >> d->log2_chroma_h : cy;
        // A palette is a table, not pixels.
        if (i == 1 && (d->flags & AV_PIX_FMT_FLAG_PAL)) {
            src[i] = f->data[i];
            continue;
        }
        src[i] = f->data[i] + sy * f->linesize[i] + sx * step;
    }
    uint8_t *dst[4] = {out, out + p->w * p->h, out + p->w * p->h + (p->w / 2) * (p->h / 2), nullptr};
    int dstStride[4] = {p->w, p->w / 2, p->w / 2, 0};
    sws_scale(p->sws, src, f->linesize, 0, ch, dst, dstStride);
    av_frame_unref(f);
    return true;
}

extern "C" void ost_vfx_player_close(void *player)
{
    delete static_cast<Player *>(player);
}

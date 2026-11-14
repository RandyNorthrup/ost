// Rendering an edited video clip, as Teams' recorder does before it sends:
// the clips in their order, each cut to its kept part, joined, with the
// chosen music mixed in under them, encoded to one H.264/AAC MP4. The edit
// arrives as an FFmpeg filter graph (built and tested in
// src/api/video_clips.rs) whose `movie`/`amovie` sources read the clips
// and whose outputs are labelled [v] and [a].
extern "C" {
#include <libavcodec/avcodec.h>
#include <libavfilter/avfilter.h>
#include <libavfilter/buffersink.h>
#include <libavformat/avformat.h>
#include <libavutil/channel_layout.h>
#include <libavutil/opt.h>
}

#include <cstring>
#include <string>

namespace {

struct Out {
    AVFormatContext *fmt = nullptr;
    AVCodecContext *venc = nullptr;
    AVCodecContext *aenc = nullptr;
    AVStream *vst = nullptr;
    AVStream *ast = nullptr;
    AVFilterGraph *graph = nullptr;
    AVFilterContext *vsink = nullptr;
    AVFilterContext *asink = nullptr;
    AVPacket *pkt = nullptr;
    AVFrame *frame = nullptr;

    ~Out()
    {
        av_frame_free(&frame);
        av_packet_free(&pkt);
        avcodec_free_context(&venc);
        avcodec_free_context(&aenc);
        avfilter_graph_free(&graph);
        if (fmt) {
            if (!(fmt->oformat->flags & AVFMT_NOFILE))
                avio_closep(&fmt->pb);
            avformat_free_context(fmt);
        }
    }
};

std::string err(int code, const char *what)
{
    char buf[AV_ERROR_MAX_STRING_SIZE] = {0};
    av_strerror(code, buf, sizeof buf);
    return std::string(what) + ": " + buf;
}

// Send `f` (or flush with nullptr) to `enc` and write what comes out.
int encode(Out &o, AVCodecContext *enc, AVStream *st, AVFrame *f)
{
    int r = avcodec_send_frame(enc, f);
    if (r < 0 && r != AVERROR_EOF)
        return r;
    while (true) {
        r = avcodec_receive_packet(enc, o.pkt);
        if (r == AVERROR(EAGAIN) || r == AVERROR_EOF)
            return 0;
        if (r < 0)
            return r;
        av_packet_rescale_ts(o.pkt, enc->time_base, st->time_base);
        o.pkt->stream_index = st->index;
        r = av_interleaved_write_frame(o.fmt, o.pkt);
        if (r < 0)
            return r;
    }
}

} // namespace

// Render `graph` (its outputs [v] and [a]) to `out` at `width` x `height`,
// 30 frames a second. Returns 0, or writes why into `error` and returns -1.
extern "C" int ost_clip_render(const char *graph_desc, const char *out, int width, int height, char *error, int error_len)
{
    auto fail = [&](const std::string &why) {
        if (error && error_len > 0) {
            std::strncpy(error, why.c_str(), error_len - 1);
            error[error_len - 1] = 0;
        }
        return -1;
    };
    Out o;
    o.graph = avfilter_graph_alloc();
    if (!o.graph)
        return fail("No memory");
    // The sinks, then the edit itself joined to them.
    int r = avfilter_graph_create_filter(&o.vsink, avfilter_get_by_name("buffersink"), "v", nullptr, nullptr, o.graph);
    if (r < 0)
        return fail(err(r, "Video sink"));
    r = avfilter_graph_create_filter(&o.asink, avfilter_get_by_name("abuffersink"), "a", nullptr, nullptr, o.graph);
    if (r < 0)
        return fail(err(r, "Audio sink"));
    AVFilterInOut *outputs = avfilter_inout_alloc();
    AVFilterInOut *aout = avfilter_inout_alloc();
    outputs->name = av_strdup("v");
    outputs->filter_ctx = o.vsink;
    outputs->pad_idx = 0;
    outputs->next = aout;
    aout->name = av_strdup("a");
    aout->filter_ctx = o.asink;
    aout->pad_idx = 0;
    aout->next = nullptr;
    AVFilterInOut *inputs = nullptr;
    r = avfilter_graph_parse_ptr(o.graph, graph_desc, &outputs, &inputs, nullptr);
    avfilter_inout_free(&outputs);
    avfilter_inout_free(&inputs);
    if (r < 0)
        return fail(err(r, "Edit"));
    r = avfilter_graph_config(o.graph, nullptr);
    if (r < 0)
        return fail(err(r, "Edit"));

    // Encoders: H.264 (yuv420p, for every player) and AAC.
    const AVCodec *vc = avcodec_find_encoder_by_name("libx264");
    if (!vc)
        vc = avcodec_find_encoder(AV_CODEC_ID_H264);
    const AVCodec *ac = avcodec_find_encoder(AV_CODEC_ID_AAC);
    if (!vc || !ac)
        return fail("No H.264 or AAC encoder");
    r = avformat_alloc_output_context2(&o.fmt, nullptr, "mp4", out);
    if (r < 0 || !o.fmt)
        return fail(err(r, "Output"));
    o.venc = avcodec_alloc_context3(vc);
    o.venc->width = width;
    o.venc->height = height;
    o.venc->pix_fmt = AV_PIX_FMT_YUV420P;
    o.venc->time_base = av_buffersink_get_time_base(o.vsink);
    o.venc->framerate = AVRational{30, 1};
    o.venc->sample_aspect_ratio = AVRational{1, 1};
    if (o.fmt->oformat->flags & AVFMT_GLOBALHEADER)
        o.venc->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
    AVDictionary *vopts = nullptr;
    av_dict_set(&vopts, "preset", "veryfast", 0);
    av_dict_set(&vopts, "crf", "23", 0);
    r = avcodec_open2(o.venc, vc, &vopts);
    av_dict_free(&vopts);
    if (r < 0)
        return fail(err(r, "Video encoder"));
    o.aenc = avcodec_alloc_context3(ac);
    o.aenc->sample_rate = av_buffersink_get_sample_rate(o.asink);
    av_buffersink_get_ch_layout(o.asink, &o.aenc->ch_layout);
    o.aenc->sample_fmt = AV_SAMPLE_FMT_FLTP;
    o.aenc->bit_rate = 128000;
    o.aenc->time_base = AVRational{1, o.aenc->sample_rate};
    if (o.fmt->oformat->flags & AVFMT_GLOBALHEADER)
        o.aenc->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
    r = avcodec_open2(o.aenc, ac, nullptr);
    if (r < 0)
        return fail(err(r, "Audio encoder"));
    // AAC takes whole frames of frame_size samples.
    av_buffersink_set_frame_size(o.asink, o.aenc->frame_size);

    o.vst = avformat_new_stream(o.fmt, nullptr);
    o.ast = avformat_new_stream(o.fmt, nullptr);
    avcodec_parameters_from_context(o.vst->codecpar, o.venc);
    avcodec_parameters_from_context(o.ast->codecpar, o.aenc);
    o.vst->time_base = o.venc->time_base;
    o.ast->time_base = o.aenc->time_base;
    r = avio_open(&o.fmt->pb, out, AVIO_FLAG_WRITE);
    if (r < 0)
        return fail(err(r, "Writing the clip"));
    AVDictionary *mopts = nullptr;
    // The index first, so it plays while it loads.
    av_dict_set(&mopts, "movflags", "+faststart", 0);
    r = avformat_write_header(o.fmt, &mopts);
    av_dict_free(&mopts);
    if (r < 0)
        return fail(err(r, "Writing the clip"));

    o.pkt = av_packet_alloc();
    o.frame = av_frame_alloc();
    bool vdone = false, adone = false;
    int64_t vlast = -1, alast = -1;
    // Take from whichever stream is behind, so the file interleaves.
    while (!vdone || !adone) {
        bool takeVideo = !vdone && (adone || av_compare_ts(vlast, o.venc->time_base, alast, o.aenc->time_base) <= 0);
        AVFilterContext *sink = takeVideo ? o.vsink : o.asink;
        r = av_buffersink_get_frame(sink, o.frame);
        if (r == AVERROR_EOF) {
            (takeVideo ? vdone : adone) = true;
            r = encode(o, takeVideo ? o.venc : o.aenc, takeVideo ? o.vst : o.ast, nullptr);
            if (r < 0)
                return fail(err(r, "Encoding"));
            continue;
        }
        if (r == AVERROR(EAGAIN))
            continue;
        if (r < 0)
            return fail(err(r, "Reading the clips"));
        if (takeVideo) {
            o.frame->pict_type = AV_PICTURE_TYPE_NONE;
            vlast = o.frame->pts;
            r = encode(o, o.venc, o.vst, o.frame);
        } else {
            alast = o.frame->pts;
            r = encode(o, o.aenc, o.ast, o.frame);
        }
        av_frame_unref(o.frame);
        if (r < 0)
            return fail(err(r, "Encoding"));
    }
    r = av_write_trailer(o.fmt);
    if (r < 0)
        return fail(err(r, "Writing the clip"));
    return 0;
}

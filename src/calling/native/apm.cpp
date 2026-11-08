// A C interface to WebRTC's AudioProcessing module (the distribution's
// webrtc-audio-processing-1): echo cancellation, noise suppression and
// gain control on a call's 48 kHz mono audio, in 10 ms frames.
#include <modules/audio_processing/include/audio_processing.h>

#include <cstdint>

extern "C" {

struct ost_apm {
  webrtc::AudioProcessing* apm;
  webrtc::StreamConfig config;
};

static void ost_apm_configure(ost_apm* a, bool echo, bool noise, int noise_level, bool gain) {
  webrtc::AudioProcessing::Config c;
  c.high_pass_filter.enabled = true;
  c.echo_canceller.enabled = echo;
  c.echo_canceller.mobile_mode = false;
  c.noise_suppression.enabled = noise;
  switch (noise_level) {
    case 0: c.noise_suppression.level = webrtc::AudioProcessing::Config::NoiseSuppression::kLow; break;
    case 1: c.noise_suppression.level = webrtc::AudioProcessing::Config::NoiseSuppression::kModerate; break;
    case 3: c.noise_suppression.level = webrtc::AudioProcessing::Config::NoiseSuppression::kVeryHigh; break;
    default: c.noise_suppression.level = webrtc::AudioProcessing::Config::NoiseSuppression::kHigh; break;
  }
  c.gain_controller1.enabled = gain;
  c.gain_controller1.mode = webrtc::AudioProcessing::Config::GainController1::kAdaptiveDigital;
  a->apm->ApplyConfig(c);
}

ost_apm* ost_apm_new(int sample_rate) {
  webrtc::AudioProcessing* apm = webrtc::AudioProcessingBuilder().Create();
  if (!apm) return nullptr;
  ost_apm* a = new ost_apm{apm, webrtc::StreamConfig(sample_rate, 1)};
  ost_apm_configure(a, true, true, 2, true);
  apm->Initialize();
  return a;
}

void ost_apm_set(ost_apm* a, bool echo, bool noise, int noise_level, bool gain) {
  ost_apm_configure(a, echo, noise, noise_level, gain);
}

// One 10 ms frame of what is played (the echo canceller's reference).
int ost_apm_render(ost_apm* a, int16_t* frame) {
  return a->apm->ProcessReverseStream(frame, a->config, a->config, frame);
}

// One 10 ms frame from the microphone, processed in place.
int ost_apm_capture(ost_apm* a, int16_t* frame, int delay_ms) {
  a->apm->set_stream_delay_ms(delay_ms);
  return a->apm->ProcessStream(frame, a->config, a->config, frame);
}

void ost_apm_free(ost_apm* a) {
  if (!a) return;
  delete a->apm;
  delete a;
}

}  // extern "C"

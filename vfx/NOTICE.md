# Third-party files

| File | Source | Licence |
|---|---|---|
| `human_segmentation_pphumanseg_2023mar.onnx` | PP-HumanSeg (PaddleSeg, PaddlePaddle authors), as packaged in [OpenCV Zoo](https://github.com/opencv/opencv_zoo/tree/main/models/human_segmentation_pphumanseg) | Apache License 2.0 |

## Downloaded at run time

These aren't in the repository or shipped with OST. OST downloads them on first need into its cache folder (`~/.cache/ost/models/`, or `$XDG_CACHE_HOME/ost/models/`), checks each against a pinned SHA-256 and uses it only if it matches.

| File | Source | Licence |
|---|---|---|
| `3dspeaker_speech_campplus_sv_en_voxceleb_16k.onnx` (voice isolation; SHA-256 `98daf9bcf1c8abf3db374fec4c27a5eda7c58705bb3f180d057b085a72a88bb5`, 29,596,979 bytes) | CAM++ speaker verification model trained on VoxCeleb, from [3D-Speaker](https://github.com/modelscope/3D-Speaker) (Alibaba DAMO Academy speech lab; ModelScope `iic/speech_campplus_sv_en_voxceleb_16k`), as exported to ONNX by sherpa-onnx; downloaded from sherpa-onnx's [speaker-recongition-models](https://github.com/k2-fsa/sherpa-onnx/releases/tag/speaker-recongition-models) release | Apache License 2.0 |

The models run with [tract](https://github.com/sonos/tract) (MIT or Apache 2.0).

The voice isolation tests that need its model load it from the path in `OST_VOICE_ISOLATION_MODEL` and are skipped without it.

`testdata/*.wav` are synthetic speech made with [Piper](https://github.com/rhasspy/piper) voice en_US libritts_r (medium; trained on LibriTTS-R, CC BY 4.0), speakers 100 and 5.

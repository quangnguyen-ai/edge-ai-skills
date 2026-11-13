# Qualcomm targets — checklist

Detail, numbers, error messages and evidence levels: [../../../../docs/knowledge/qualcomm-qairt.md](../../../../docs/knowledge/qualcomm-qairt.md) (in the `edge-ai-skills` repo, `docs/knowledge/`). Read it before deciding anything the checklist below doesn't settle.

1. **Identify the accelerator from the SoC, not from a doc's claim**: DSP-only (e.g. Hexagon V66) → SNPE DSP / `libQnnDsp.so`; HTP SoCs → `libQnnHtp.so`. Match `ADSP_LIBRARY_PATH` to the `hexagon-vXX` skel and the device runtime to the SDK version.
2. **Pin the toolchain** (QAIRT version + Python deps) in a container; sanity-check the float ONNX in ONNX Runtime before converting.
3. **Check op limits** before converting: rank-5 tensors (DFL/GFL heads) don't run on DSP-class targets — export without them and decode on the CPU. Multi-output models need the C++ API with unconsumed tensors exposed.
4. **Fix layout and preprocessing at conversion time**: NHWC input, uint8 BGR without normalization where the model allows (or bake normalization into the ONNX); confirm with `qairt-dlc-info`.
5. **Calibrate with the exact deployment preprocessing and layout**, per-channel weights; W8A16 if W8A8 loses too much (see the `quantization` skill).
6. **HTP runtime**: zero-copy uint8 input when input scale ≈ 1/255, DMA-BUF shared buffers — follow the pitfalls in the knowledge file.
7. **Measure** with a persistent C++ runtime pinned to the big cores, full eval set, against your own FP32 baseline.
8. **Record** only a new non-obvious lesson or a corrected one in the knowledge file (date + evidence label, no numbers); measurements go in the project's own report.

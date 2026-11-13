# Qualcomm QAIRT (SNPE / QNN) — field notes

**Last reviewed**: 2026-10-13 · **SDK**: QAIRT 2.36.0 · **Verified device**: QRB5165 / SM8250 (cDSP Hexagon V66) · **Not yet verified**: HTP V73 (SM8550)

Only non-obvious, Qualcomm-specific lessons are kept here; measurements stay with the project that produced them. The procedure that uses this is the `model-deployment` skill (`references/qualcomm.md` checklist). Update a lesson when a new SDK version or device changes it — and keep the evidence label honest.

Evidence levels used below: **[measured]** = observed on a real device (QRB5165 / SM8250, cDSP Hexagon V66, QAIRT 2.36); **[docs]** = from engineering notes with exact error messages, not re-run here; **[assumption]** = not verified on hardware — check before relying on it.

## 1. Know the accelerator before choosing a backend

| SoC generation | Accelerator | Runtime backend |
|---|---|---|
| Older (e.g. QRB5165 / SM8250) | cDSP Hexagon **V66, no HTP** | SNPE DSP runtime / `libQnnDsp.so`, skel `hexagon-v66` |
| Newer (e.g. SM8550) | **HTP** (V73) | `libQnnHtp.so`, skel `hexagon-v73`, ideally an offline-prepared context binary |

- Using the HTP backend on a V66-only SoC fails with `Unsupported SnapdragonModel by HTP backend` **[measured]**. A doc claiming "HTP" on such a chip is wrong — check the chip, not the doc.
- Set `ADSP_LIBRARY_PATH` to the matching `lib/hexagon-vXX/unsigned` directory, and `LD_LIBRARY_PATH` to the SDK's aarch64 lib dir **[measured]**.
- HTP V73 offline prepare (`qnn-context-binary-generator --backend libQnnHtp.so …`, or `--htp_socs` at conversion depending on the QAIRT version) **[assumption]** — verify on the device; mixed SDK/runtime versions show up as `undefined symbol …zdl::DlSystem…` **[measured]**.

## 2. Toolchain

```
model.onnx ─ qairt-converter ─▶ float .dlc ─ qairt-quantizer (+ calibration raws) ─▶ INT8 .dlc ─▶ device: snpe-net-run / qnn-net-run / C++ API
```

- Pin the whole toolchain in a container: QAIRT version, and Python deps (`protobuf`, `onnx`, `numpy<2` — mismatches give `onnx.AttributeProto = None`) **[measured]**. Version the device runtime next to the SDK that produced the model; one model-zoo manifest records SDK version, quantization, input size, accuracy, latency per artifact **[docs]**.
- Before quantizing, sanity-check the float model in ONNX Runtime on the host (the `model-deployment` golden reference) **[measured]**.

## 3. Op and graph constraints

- **DSP V66 cannot finalize rank-5 tensors.** Detection heads with DFL / GFL distributions (`[N,4,bins,H,W]` + softmax) fail with `Input has incorrect Rank 5`. Export the model without the DFL post-processing and do softmax + integral decode on the CPU **[measured]**. Newer HTP may run it — **[assumption]**, test before removing the CPU decode.
- **SNPE exposes only the last output by default.** Multi-output models need `SNPEBuilder::setUnconsumedTensorsAsOutputs(true)` in C++; the CLI tools struggle, so evaluate multi-output models with a C++ harness **[measured]**.
- Output tensor names follow the ONNX graph — glob outputs instead of hard-coding `output.raw` **[measured]**.

## 4. Layout and preprocessing — the biggest free win

- Check the DLC's input layout: `qairt-dlc-info -i model.dlc | grep -iE "Input|dimension"` — `[1,3,H,W]` NCHW vs `[1,H,W,3]` NHWC, and feed raw files to match **[measured]**.
- Convert to NHWC at conversion time (`--source_model_input_layout <in> NCHW --desired_input_layout <in> NHWC`) so the device never transposes **[measured]**.
- Prefer models whose input is the camera's native **uint8 BGR, no normalization**; otherwise bake the normalization into the ONNX graph (Transpose → channel Gather → scale → mean/std in front of the old input) so the runtime only resizes and copies **[measured]**.
  - On the same network, switching only the preprocessing path (normalized RGB NCHW → raw BGR NHWC) gave a large speedup on its own **[measured]**.
- When a model's expected preprocessing is unclear, run the ONNX on the host with each candidate (BGR/RGB × raw/normalized) and keep the one that gives correct, high-score detections; garbage classes mean wrong preprocessing, not a bad quantization **[measured]**.

## 5. Zero-copy I/O on HTP (QNN)

All **[docs]**:
- If the input quantization is scale ≈ 1/255, offset 0, the uint8 image *is* the quantized tensor: copy it straight in and skip float conversion + quantize — input preparation drops to almost nothing.
- Shared buffers come from the DMA-BUF heap (`/dev/dma_heap/system`), registered with `memRegister` as `QNN_HTP_MEM_SHARED_BUFFER`, 4 KB aligned; `memfd_create` buffers fail with `fastrpc memory map for fd failed`.
- `Qnn_Tensor` v1 keeps `clientBuf` and `memHandle` in a **union**: zero `clientBuf` first, then set `memType` and `memHandle`, and never write `clientBuf` afterwards (symptom: `Failed to find memHandle`).
- Several outputs can share one aligned buffer, each registered at its own offset. Dequantize outputs with cached scale/offset, or post-process directly in uint8.
- Release order: shared buffer users → `memDeRegister` → close fd → `munmap`.

## 6. Model choice and licensing

Check the model's license at intake: AGPL-licensed detectors (e.g. Ultralytics YOLOv8/v11) carry obligations a commercial product may not accept; Apache-2.0 alternatives (YOLOX, DAMO-YOLO) deployed fine on V66 **[measured; licence terms from the model repos]**.

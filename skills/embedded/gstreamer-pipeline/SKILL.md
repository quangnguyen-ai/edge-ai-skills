---
name: gstreamer-pipeline
description: Build, debug, and tune real-time GStreamer video pipelines for edge analytics — RTSP/H.264/H.265 ingest, hardware decode, zero-copy buffers, inference in the stream (DeepStream, or appsink/appsrc to custom C++). Use when the user works on a gst-launch pipeline or a GStreamer C/C++ app, puts a model into a video stream, or reports latency, stutter, frame drops, caps negotiation failures, reconnect problems, or memory growth in a video pipeline.
---

# GStreamer pipelines for edge analytics

For live analytics the rule is **latest frame wins**: bounded queues, an explicit drop policy, and frames that stay in device memory end to end. Most latency and memory bugs are an unbounded queue or a hidden CPU copy.

Read `docs/agents/execution-environment.md` (if it exists) first. If pipelines only run on the target, give the user exact commands and the debug env vars below, and work from what they paste back.

## 1. Inventory the platform

`gst-inspect-1.0` on the **target**: which hardware decoders, converters, and inference elements exist, and their caps.

- Jetson: `nvv4l2decoder`, `nvvideoconvert` / `nvvidconv`, `memory:NVMM` caps; DeepStream adds `nvstreammux`, `nvinfer`, `nvtracker`.
- Other SoCs: V4L2 stateful/stateless decoders (`v4l2h264dec`, `v4l2slh264dec`), vendor elements (e.g. NXP `vpudec`), VA-API on x86.

Done when the decode → convert → infer → sink chain for this platform is named element by element, with the memory type at each link.

## 2. Prototype with gst-launch, grow incrementally

Start from source → decode → `fakesink sync=false` and add one element at a time, checking FPS at each step (`fpsdisplaysink video-sink=fakesink text-overlay=false -v`).

Typical RTSP ingest:

```
rtspsrc location=… latency=… protocols=tcp ! rtph264depay ! h264parse ! <hw decoder> ! <hw convert> ! …
```

- `rtspsrc latency` is the jitter-buffer size in ms (default 2000) — the first knob for live latency. Lower it until you see packet-loss artifacts, then back off.
- `protocols=tcp` avoids UDP loss over bad links at some latency cost.

Done when the gst-launch line reaches target FPS with the real stream, and is saved in the repo.

## 3. Keep frames on the device

Every CPU `videoconvert`, `videoscale`, or map-to-CPU in the middle of the pipeline is a full-frame copy. Keep device memory caps (e.g. `video/x-raw(memory:NVMM)`) from the decoder to the inference input; do color conversion and scaling on the hardware converter. Map to CPU only at the very end, and only for what the CPU actually needs (metadata, a thumbnail).

Done when the negotiated caps graph (step 6) shows device memory on every link up to inference.

## 4. Queues, threads, and drop policy

- A `queue` is a thread boundary. Put one after every `tee` branch and before slow elements.
- For live analytics: `queue leaky=downstream max-size-buffers=1` (or a small N) in front of inference — the analytics branch drops old frames instead of accumulating latency. A recording branch may instead need lossless queues; decide per branch.
- `appsink`: `sync=false drop=true max-buffers=1` for analytics. `emit-signals` or `pull-sample` from your own thread.
- Never block in a pad probe or in an appsink callback running on a streaming thread — hand the frame off.

Done when every queue has an explicit size and leak policy, and the drop policy is written down per branch.

## 5. appsink / appsrc in C++

- `appsink`: every `gst_app_sink_pull_sample` needs `gst_sample_unref`; every `gst_buffer_map` needs `gst_buffer_unmap`. Prefer RAII wrappers so error paths release too.
- `appsrc`: set caps, `is-live=true`, `format=time`; timestamp buffers (PTS) or use `do-timestamp=true`; choose `block` vs dropping when downstream is slow.
- Carry the frame's PTS through inference to the result, so results can be matched to frames and latency measured.

## 6. Debugging toolkit

- Logs: `GST_DEBUG=2,<element>:6` (levels 1–7; start low, raise per element).
- Graph: set `GST_DEBUG_DUMP_DOT_DIR=/tmp/dots` and call `GST_DEBUG_BIN_TO_DOT_FILE` (gst-launch dumps automatically on state changes) → `dot -Tsvg`. Shows the negotiated caps on every link — first stop for `not-negotiated` errors.
- Latency: `GST_TRACERS="latency(flags=pipeline+element)" GST_DEBUG="GST_TRACER:7"` for per-element latency. GstShark adds `proctime`, `framerate`, `queuelevel` tracers.
- Leaks: `GST_TRACERS=leaks` reports GStreamer objects alive at shutdown.
- Watch the bus: errors, warnings, QoS messages (drops), latency messages.

## 7. Robustness

- Cameras disconnect: handle bus errors/EOS from the source by tearing down and rebuilding the source bin with backoff; don't restart the whole process.
- State changes are async — wait for them (`gst_element_get_state`) before assuming PLAYING.
- Recording/file branches: a slow or stalling sink (SD card, network share) must not back up the whole pipeline — bound the queue in front of it, drop on overflow, and prefer a fast medium. App-level writer threads block on data, never `usleep`-poll.
- Soak test: run hours on a real stream; track RSS and queue levels over time. Growth with stable queue levels = a leak (`embedded-debugging` skill); growth with rising queue levels = a drop-policy bug.

## Completion

Done when: the pipeline is in the repo (gst-launch line or app), its negotiated-caps graph shows no unintended CPU copies, per-element and end-to-end latency (p50/p99) are measured on the target and recorded in the notes, every queue has an explicit policy, and a soak run shows flat memory.

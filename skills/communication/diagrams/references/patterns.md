# Diagram patterns for embedded / edge systems

Start from the pattern that matches the question, then replace every name with the real token from the code (class, stage, config key, element name). All snippets render with `scripts/render.sh`.

Default look: **white page, soft tinted boxes** — see [style.md](style.md) for the palette and rules. Add only the `classDef`s you use:

```
classDef start fill:#1F2A37,stroke:#12181F,color:#FFFFFF,stroke-width:2px
classDef purple fill:#EFE7F7,stroke:#6A3D96,color:#4A2870,stroke-width:1.8px
classDef hot fill:#FBEAE2,stroke:#B0431C,color:#7E2E10,stroke-width:1.8px
classDef amber fill:#FAF0D9,stroke:#A0730B,color:#6E4E06,stroke-width:1.8px
classDef slate fill:#E8EEF2,stroke:#4A6070,color:#2C3E4C,stroke-width:1.8px
classDef finish fill:#6A3D96,stroke:#4A2870,color:#FFFFFF,stroke-width:2px
```

## 1. Per-frame data flow (pipeline)

Question: *what happens to one frame, where does it live, what does each hop cost?* Edge labels carry format, resolution, memory type, and (optionally) time.

```mermaid
flowchart LR
  cam([Camera]):::start -->|"H.264 / RTSP"| dec[HW decoder]
  dec -->|"NV12 1920x1080<br/>device memory"| pre[Preprocess<br/>resize + normalize]
  pre -->|"FP16 NCHW 640x640"| infer[TensorRT engine]:::hot
  infer -->|"raw boxes"| post[Decode + NMS]
  post -->|"≤100 boxes<br/>host copy"| app([Application]):::finish

  classDef start fill:#1F2A37,stroke:#12181F,color:#FFFFFF,stroke-width:2px
  classDef purple fill:#EFE7F7,stroke:#6A3D96,color:#4A2870,stroke-width:1.8px
  classDef hot fill:#FBEAE2,stroke:#B0431C,color:#7E2E10,stroke-width:1.8px
  classDef finish fill:#6A3D96,stroke:#4A2870,color:#FFFFFF,stroke-width:2px
```

## 2. Layered architecture

Question: *what are the layers and which way do dependencies point?* One box per layer or component, top to bottom, arrows pointing down only.

```mermaid
flowchart TB
  app[Application<br/>multi-model logic]
  subgraph lib[Library]
    api[Public API<br/>Engine::process]
    task[Tasks<br/>Detection · Segmentation]
    stages[Pre / Post processors]
    be[Backend interface]
  end
  subgraph backends[Backends]
    trt[TensorRT]
    ort[ONNX Runtime]
    tfl[TFLite]
  end
  app --> api --> task --> stages
  task --> be
  be --> trt & ort & tfl
```

## 3. Threads and queues

Question: *which thread does what, where can frames pile up, what gets dropped?* Queues are nodes, labelled with size and policy.

```mermaid
flowchart LR
  subgraph T1[capture thread]
    cap[grab frame]
  end
  q1[["queue · max 2<br/>drop oldest"]]:::hot
  subgraph T2[inference thread]
    inf[preprocess + infer]
  end
  q2[["queue · max 4<br/>block"]]
  subgraph T3[output thread]
    out[draw + encode]
  end
  cap --> q1 --> inf --> q2 --> out

  classDef hot fill:#FBEAE2,stroke:#B0431C,color:#7E2E10,stroke-width:1.8px
```

## 4. Sequence — host, library, device

Question: *who calls whom, in what order, where are the syncs?* Keep to one scenario (init, steady-state frame, or error path).

```mermaid
sequenceDiagram
  participant App
  participant Eng as Engine
  participant GPU
  App->>Eng: process(frame)
  Eng->>GPU: H2D copy (async)
  Eng->>GPU: preprocess kernel
  Eng->>GPU: enqueueV3
  Eng->>GPU: decode + NMS kernels
  Eng->>GPU: D2H copy (boxes only)
  GPU-->>Eng: stream sync
  Eng-->>App: Result {boxes, timing}
```

## 5. State machine

Question: *what states exist and what moves between them?* Include the failure and recovery edges — they are usually why the diagram is needed.

```mermaid
stateDiagram-v2
  [*] --> Idle
  Idle --> WarmingUp: init(config) ok
  Idle --> Failed: invalid config
  WarmingUp --> Running: history full
  Running --> WarmingUp: reset (toggle / resize)
  Running --> Reconnecting: source lost
  Reconnecting --> WarmingUp: source back
  Reconnecting --> Failed: retries exhausted
  Failed --> Idle: re-init
```

## 6. Deployment

Question: *what runs where, and how do the machines talk?*

```mermaid
flowchart LR
  subgraph host[Dev host · x86]
    src[source tree]
    sync[target.sh]
  end
  subgraph board[Target board · aarch64]
    build[build/ + binaries]
    svc[production service]
    cam([camera])
  end
  gcs([Ground station / viewer])
  src --> sync -->|"rsync + ssh"| build
  cam --> svc -->|"RTSP"| gcs
```

## 7. Latency budget

Question: *where does the frame time go?* Use real measured numbers (p50 or p99 — say which). Mermaid's gantt needs dates; use `dateFormat x` with millisecond offsets.

```mermaid
gantt
  title Frame budget 33 ms (p99)
  dateFormat x
  axisFormat %L ms
  section Capture
  decode        :0, 4
  section GPU
  preprocess    :4, 6
  inference     :6, 18
  postprocess   :18, 20
  section Host
  tracking      :20, 23
  encode + send :23, 30
```

## 8. Interfaces (class diagram)

Question: *what must a new backend/stage implement?* Interfaces and one or two implementations only — never every class.

```mermaid
classDiagram
  class IBackend {
    <<interface>>
    +load(path) bool
    +infer(inputs, outputs) bool
    +inputShape(name) Shape
  }
  class TensorRTBackend
  class OnnxRuntimeBackend
  IBackend <|.. TensorRTBackend
  IBackend <|.. OnnxRuntimeBackend
```

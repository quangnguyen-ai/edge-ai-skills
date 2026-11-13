# RAII wrappers and check macros (non-GPU)

Minimal, copy-ready. Adapt names to the repo's conventions.

## Check macros

```cpp
// check.hpp
#pragma once
#include <string>

namespace mylib {

// Records the failing call; the API boundary turns it into an error code.
struct Error {
    int code = 0;
    std::string message;   // "trt_load(engine.plan) failed: file not found at engine.cpp:42"
    explicit operator bool() const { return code != 0; }
};

std::string format_error(const char* call, const char* what, const char* file, int line);

}  // namespace mylib

// Status-returning SDK calls: adapt the predicate and message per SDK.
#define MYLIB_CHECK(cond, msg)                                                        \
    do {                                                                              \
        if (!(cond))                                                                  \
            return ::mylib::Error{1, ::mylib::format_error(#cond, (msg), __FILE__, __LINE__)}; \
    } while (0)

// CUDA / OpenCL check macros: gpu-kernel-engineering → references/host-code.md.
```

Functions that can fail return `mylib::Error` (or `std::expected` in C++23); constructors that can fail become a static `create()` returning the object or the error.

## GPU handles

CUDA buffers, pinned memory, streams, events, and OpenCL objects: `gpu-kernel-engineering` → `references/host-code.md`.

## TensorRT

```cpp
// TensorRT 10: objects are released with plain delete.
template <typename T> using TrtPtr = std::unique_ptr<T>;

struct TrtModel {               // declaration order = reverse destruction order
    TrtPtr<nvinfer1::IRuntime> runtime;
    TrtPtr<nvinfer1::ICudaEngine> engine;
    TrtPtr<nvinfer1::IExecutionContext> context;
};
// Members are destroyed bottom-up: context, then engine, then runtime.
```

Bind I/O by tensor name (`setTensorAddress(name, ptr)`), never by index.

## GStreamer

```cpp
// GLib auto-cleanup works for GStreamer types.
g_autoptr(GstSample) sample = gst_app_sink_pull_sample(GST_APP_SINK(sink));
if (!sample) return Error{1, "appsink returned no sample (EOS?)"};
GstBuffer* buf = gst_sample_get_buffer(sample);          // borrowed, not owned

struct BufferMap {                                        // map/unmap in one scope
    GstBuffer* buf; GstMapInfo info{};
    bool ok;
    BufferMap(GstBuffer* b, GstMapFlags f) : buf(b), ok(gst_buffer_map(b, &info, f)) {}
    ~BufferMap() { if (ok) gst_buffer_unmap(buf, &info); }
};
```

## Owned thread + bounded queue

```cpp
template <typename T>
class BoundedQueue {
public:
    enum class Full { DropOldest, DropNewest, Block };
    BoundedQueue(size_t cap, Full policy) : cap_(cap), policy_(policy) {}

    bool push(T v) {
        std::unique_lock lk(m_);
        if (q_.size() == cap_) {
            if (policy_ == Full::DropNewest) return false;
            if (policy_ == Full::DropOldest) q_.pop_front();
            else not_full_.wait(lk, [&] { return q_.size() < cap_ || stop_; });
            if (stop_) return false;
        }
        q_.push_back(std::move(v));
        not_empty_.notify_one();
        return true;
    }
    std::optional<T> pop() {
        std::unique_lock lk(m_);
        not_empty_.wait(lk, [&] { return !q_.empty() || stop_; });
        if (q_.empty()) return std::nullopt;
        T v = std::move(q_.front()); q_.pop_front();
        not_full_.notify_one();
        return v;
    }
    void stop() { { std::lock_guard lk(m_); stop_ = true; } not_empty_.notify_all(); not_full_.notify_all(); }
private:
    std::mutex m_; std::condition_variable not_empty_, not_full_;
    std::deque<T> q_; size_t cap_; Full policy_; bool stop_ = false;
};

class Worker {
public:
    explicit Worker(BoundedQueue<Frame>& in) : in_(in), t_([this] { run(); }) {}
    ~Worker() { in_.stop(); if (t_.joinable()) t_.join(); }   // stop, then join: never detach
private:
    void run() { while (auto f = in_.pop()) process(*f); }
    BoundedQueue<Frame>& in_;
    std::thread t_;                                              // declared last: starts after members exist
};
```

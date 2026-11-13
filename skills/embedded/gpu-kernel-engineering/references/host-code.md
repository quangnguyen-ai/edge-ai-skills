# Host-side GPU code — CUDA and OpenCL

The code around the kernels: ownership, error checks, streams, memory, build. General C++ rules (error type at the API boundary, threads, queues, CMake structure) are in the `cpp-engineering` skill; this file is what changes when the handle is a GPU one.

## Rules

- **No naked GPU resource calls outside a wrapper**: `cudaMalloc/cudaFree`, `cudaMallocHost/cudaFreeHost`, `cudaStreamCreate/Destroy`, `cudaEventCreate/Destroy`, `clCreate*/clRelease*`. One move-only owning type per handle kind. Hand-paired allocate/free calls drift apart as code grows (seen: hundreds of allocations, a quarter fewer frees).
- Buffers are typed and sized (`DeviceBuffer<float>`), allocated once at init, reused per frame.
- **Every CUDA/OpenCL call checked** with the call text and file:line. A kernel launch is followed by `cudaGetLastError()` (launch-config errors); execution faults surface at the next synchronising call — check that one too. Unchecked calls by the hundred are the norm in grown codebases; a failure then shows up frames later, somewhere else.
- **Streams**: one explicit stream per pipeline thread; never the legacy default stream (it synchronises with every stream in the process — `cudaStreamNonBlocking` or `cudaStreamPerThread`). Cross-stream ordering with events (`cudaEventRecord` / `cudaStreamWaitEvent`), never `cudaDeviceSynchronize` in the loop.
- **Transfers**: pinned host memory, async copies on the pipeline's stream, read back only what the host needs (a few scalars, not the frame). Each readback on an in-order queue is a barrier.
- **Build**: profiling builds `RelWithDebInfo` + `-lineinfo`; never `-G` in anything timed. Kernel binary caches (OpenCL `.bin`, CUDA compute cache) go stale after a signature change — rebuild and clear them.
- CUDA Graphs bake kernel arguments by value — stable buffer addresses only (see the catalog and the `model-deployment` runtime-optimization reference).

## Check macros

Uses the library's `Error` type and `format_error()` from the `cpp-engineering` snippets.

```cpp
#define MYLIB_CUDA_CHECK(call)                                                        \
    do {                                                                              \
        cudaError_t e_ = (call);                                                      \
        if (e_ != cudaSuccess)                                                        \
            return ::mylib::Error{static_cast<int>(e_),                               \
                ::mylib::format_error(#call, cudaGetErrorString(e_), __FILE__, __LINE__)}; \
    } while (0)

// After a kernel launch: launch-configuration errors are reported here,
// execution faults at the next synchronising call (check that one too).
#define MYLIB_CUDA_CHECK_LAUNCH() MYLIB_CUDA_CHECK(cudaGetLastError())

#define MYLIB_CL_CHECK(call)                                                          \
    do {                                                                              \
        cl_int e_ = (call);                                                           \
        if (e_ != CL_SUCCESS)                                                         \
            return ::mylib::Error{e_, ::mylib::format_error(#call, "OpenCL error", __FILE__, __LINE__)}; \
    } while (0)
```

## CUDA wrappers

```cpp
template <typename T>
class DeviceBuffer {
public:
    DeviceBuffer() = default;
    static Error create(DeviceBuffer& out, size_t count) {
        T* p = nullptr;
        MYLIB_CUDA_CHECK(cudaMalloc(&p, count * sizeof(T)));
        out = DeviceBuffer(p, count);
        return {};
    }
    ~DeviceBuffer() { if (ptr_) cudaFree(ptr_); }
    DeviceBuffer(DeviceBuffer&& o) noexcept : ptr_(o.ptr_), count_(o.count_) { o.ptr_ = nullptr; o.count_ = 0; }
    DeviceBuffer& operator=(DeviceBuffer&& o) noexcept {   // old buffer is freed when `o` dies
        std::swap(ptr_, o.ptr_);
        std::swap(count_, o.count_);
        return *this;
    }
    DeviceBuffer(const DeviceBuffer&) = delete;
    DeviceBuffer& operator=(const DeviceBuffer&) = delete;

    T* get() const { return ptr_; }
    size_t size() const { return count_; }
    size_t bytes() const { return count_ * sizeof(T); }
private:
    DeviceBuffer(T* p, size_t n) : ptr_(p), count_(n) {}
    T* ptr_ = nullptr;
    size_t count_ = 0;
};

// Pinned host memory: same shape with cudaMallocHost / cudaFreeHost.

struct StreamDeleter { void operator()(cudaStream_t s) const { if (s) cudaStreamDestroy(s); } };
using Stream = std::unique_ptr<std::remove_pointer_t<cudaStream_t>, StreamDeleter>;

struct EventDeleter { void operator()(cudaEvent_t e) const { if (e) cudaEventDestroy(e); } };
using Event = std::unique_ptr<std::remove_pointer_t<cudaEvent_t>, EventDeleter>;

inline Error make_stream(Stream& out) {
    cudaStream_t s = nullptr;
    MYLIB_CUDA_CHECK(cudaStreamCreateWithFlags(&s, cudaStreamNonBlocking));
    out.reset(s);
    return {};
}
```

Verified: compiled with nvcc (C++17) and run on an Ampere GPU — the check macro reports `cudaMemcpy(...) failed: invalid argument at <file>:<line>`, move-assign frees the old buffer.

## OpenCL wrappers

```cpp
template <typename H, cl_int (*Release)(H)>
struct ClDeleter { void operator()(H h) const { if (h) Release(h); } };

using ClMem     = std::unique_ptr<std::remove_pointer_t<cl_mem>,     ClDeleter<cl_mem, clReleaseMemObject>>;
using ClKernel  = std::unique_ptr<std::remove_pointer_t<cl_kernel>,  ClDeleter<cl_kernel, clReleaseKernel>>;
using ClProgram = std::unique_ptr<std::remove_pointer_t<cl_program>, ClDeleter<cl_program, clReleaseProgram>>;
using ClQueue   = std::unique_ptr<std::remove_pointer_t<cl_command_queue>, ClDeleter<cl_command_queue, clReleaseCommandQueue>>;
```

Define `CL_TARGET_OPENCL_VERSION` (e.g. 300 or 120 to match the driver) before including `CL/cl.h`.

## CMake for CUDA

- Enable the language (`project(... LANGUAGES CXX CUDA)` or `enable_language(CUDA)`), use `find_package(CUDAToolkit)` and `CUDA::cudart` — not the deprecated `find_package(CUDA)`.
- `CMAKE_CUDA_ARCHITECTURES` per board (Xavier 72, Orin 87, desktop as needed). **CMake < 3.18 ignores it silently** and nvcc falls back to an old default arch, so fp16 intrinsics fail to link — on old CMake (older JetPack images ship 3.16) add `-gencode arch=compute_XX,code=sm_XX` to `CMAKE_CUDA_FLAGS` explicitly. Changing `CMAKE_CUDA_COMPILER` needs `cmake` run twice.
- `nvcc` may be missing from a non-interactive shell's `PATH` on the board; point `CMAKE_CUDA_COMPILER` at `/usr/local/cuda/bin/nvcc`.

```cmake
if(MYLIB_WITH_CUDA)
  enable_language(CUDA)
  find_package(CUDAToolkit REQUIRED)
  if(NOT DEFINED CMAKE_CUDA_ARCHITECTURES)
    set(CMAKE_CUDA_ARCHITECTURES 87)          # Orin; override per board
  endif()
  target_sources(mylib PRIVATE src/cuda/preprocess.cu)
  target_link_libraries(mylib PRIVATE CUDA::cudart)
  target_compile_definitions(mylib PRIVATE MYLIB_WITH_CUDA)
  target_compile_options(mylib PRIVATE $<$<COMPILE_LANGUAGE:CUDA>:-lineinfo>)
endif()
```

OpenCL: `find_package(OpenCL REQUIRED)` and link `OpenCL::OpenCL` on the target; mobile SoC vendors may ship the ICD loader under a vendor path — find it with `find_library` and a documented `-D…_ROOT`.

## Review checklist — GPU host code

- [ ] Every new GPU handle (buffer, pinned buffer, stream, event, `cl_*`) is owned by an RAII type.
- [ ] Every new CUDA/OpenCL call is checked; kernel launches have a launch check; the next sync is checked.
- [ ] GPU work goes on an explicit non-default stream; cross-stream dependencies use events.
- [ ] Host↔device copies are async from pinned memory; only what the host needs is read back.
- [ ] No `cudaDeviceSynchronize`/`clFinish` in the per-frame path unless the host needs the value right there.
- [ ] CUDA build flags: `-lineinfo` for profiling, no `-G` in timed builds; CUDA architectures set for every supported board.

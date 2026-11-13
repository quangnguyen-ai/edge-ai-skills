# CMake for C++ / TensorRT edge projects

CUDA language, architectures, and the old-CMake `-gencode` fallback: `gpu-kernel-engineering` → `references/host-code.md` → "CMake for CUDA".

## Rules

- **Targets, not globals.** `target_compile_options`, `target_compile_definitions`, `target_include_directories`, `target_link_libraries` with `PRIVATE/PUBLIC/INTERFACE`. No `CMAKE_CXX_FLAGS` edits, no `add_compile_definitions`, no `include_directories`. A global `-O3` silently overrides the build type.
- **Build type** defaults to `Release` only when unset and single-config; `RelWithDebInfo` for profiling.
- **Options are cached.** `option()` only sets a default when the cache variable doesn't exist: a parent project must set variables *before* `add_subdirectory()`, and a changed default needs a fresh build dir. A backend must not default ON where its toolchain cannot exist — detect the platform, or fail at configure with the option to pass.
- **One `CMakeLists.txt` per directory**, each defining its own targets. A 700-line root file is a sign the structure lives in the build script instead of the tree.
- **`CMAKE_EXPORT_COMPILE_COMMANDS ON`** so clangd and tools can navigate.
- Optional vendor SDKs: `find_path`/`find_library` with a documented `-D<SDK>_ROOT` override; only the targets that need the SDK link it; log clearly when a target is skipped.
- Install + export a package config (`install(EXPORT …)`, `<lib>-config.cmake`) so consumers use `find_package(mylib)`.
- Boards often ship old CMake (some JetPack images: 3.16 — no presets, no `CMAKE_CUDA_ARCHITECTURES`); check `cmake --version` on the target before relying on newer features.
- **Presets** (`CMakePresets.json`, CMake ≥ 3.19) name the supported configurations: `linux-release`, `jetson-release`, `windows-msvc`.

## Skeleton

```cmake
cmake_minimum_required(VERSION 3.18)
project(mylib VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()

option(MYLIB_WITH_CUDA     "CUDA backend"     OFF)   # block: host-code.md
option(MYLIB_WITH_TENSORRT "TensorRT backend" OFF)
if(CMAKE_SOURCE_DIR STREQUAL PROJECT_SOURCE_DIR)   # PROJECT_IS_TOP_LEVEL needs CMake 3.21
  set(MYLIB_TOP_LEVEL ON)
else()
  set(MYLIB_TOP_LEVEL OFF)
endif()
option(MYLIB_BUILD_TESTS   "Tests"            ${MYLIB_TOP_LEVEL})

add_library(mylib)
add_library(mylib::mylib ALIAS mylib)
target_sources(mylib PRIVATE src/engine.cpp src/config.cpp)
target_include_directories(mylib
  PUBLIC  $<BUILD_INTERFACE:${PROJECT_SOURCE_DIR}/include> $<INSTALL_INTERFACE:include>
  PRIVATE src)

if(MSVC)
  target_compile_options(mylib PRIVATE /W4 /permissive- /utf-8)
else()
  target_compile_options(mylib PRIVATE -Wall -Wextra -Wpedantic)
endif()

include(GenerateExportHeader)
generate_export_header(mylib EXPORT_FILE_NAME ${PROJECT_BINARY_DIR}/include/mylib/export.hpp)
target_include_directories(mylib PUBLIC $<BUILD_INTERFACE:${PROJECT_BINARY_DIR}/include>)

# CUDA / OpenCL backends: the "CMake for CUDA" block in gpu-kernel-engineering → host-code.md goes here.

if(MYLIB_WITH_TENSORRT)
  find_path(TENSORRT_INCLUDE_DIR NvInfer.h HINTS ${TENSORRT_ROOT} PATH_SUFFIXES include)
  find_library(NVINFER_LIB nvinfer HINTS ${TENSORRT_ROOT} PATH_SUFFIXES lib lib64)
  if(NOT TENSORRT_INCLUDE_DIR OR NOT NVINFER_LIB)
    message(FATAL_ERROR "TensorRT not found: pass -DTENSORRT_ROOT=<dir>")
  endif()
  target_include_directories(mylib PRIVATE ${TENSORRT_INCLUDE_DIR})
  target_link_libraries(mylib PRIVATE ${NVINFER_LIB})
  target_compile_definitions(mylib PRIVATE MYLIB_WITH_TENSORRT)
endif()

if(MYLIB_BUILD_TESTS)
  enable_testing()
  add_subdirectory(tests)
endif()
```

On Jetson, TensorRT lives in the system paths (`/usr/include/aarch64-linux-gnu`, `/usr/lib/aarch64-linux-gnu`) and is found without a root.

## New project

```
<name>/
├── CMakeLists.txt          # skeleton above
├── CMakePresets.json       # if the board's CMake ≥ 3.19
├── include/<name>/         # public headers only
├── src/                    # implementation, one subdir per backend
├── tests/                  # GoogleTest (FetchContent or system package), CTest
├── tools/                  # benches, offline batch, parity tools
├── config/                 # profiles
├── docs/                   # overview, diagrams/
├── workspace/              # scratch, gitignored
├── .clang-format  .gitignore  .gitattributes
├── CLAUDE.md               # onboard-codebase template
├── target.sh  .target.env.example   # target-workflow skill
```

Done when a clean clone configures, builds, and passes one test on the target with the documented command.

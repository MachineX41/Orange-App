cmake_minimum_required(VERSION 3.24)
project(OrangeOCRHelper CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_OSX_ARCHITECTURES arm64)
set(CMAKE_OSX_DEPLOYMENT_TARGET 26.0)
set(CMAKE_BUILD_TYPE Release)

# Static helper binary: no dylibs outside the bundle.
set(BUILD_SHARED_LIBS OFF)
set(GGML_BACKEND_DL OFF)
set(GGML_NATIVE OFF)
set(GGML_CPU ON)
set(GGML_ACCELERATE ON)
set(GGML_BLAS ON)
# Apple Accelerate provides the BLAS vendor on macOS.
set(GGML_BLAS_VENDOR Apple)
set(GGML_METAL ON)
set(GGML_METAL_EMBED_LIBRARY ON)
set(GGML_OPENMP OFF)

# llama.cpp only: the single pinned revision below. No Python/Paddle/ONNX/Tesseract/MLX.
set(LLAMA_BUILD_COMMON ON)
set(LLAMA_BUILD_MTMD ON)
set(LLAMA_BUILD_APP OFF)
set(LLAMA_BUILD_TOOLS OFF)
set(LLAMA_BUILD_SERVER OFF)
set(LLAMA_BUILD_TESTS OFF)
set(LLAMA_BUILD_EXAMPLES OFF)
set(LLAMA_BUILD_UI OFF)
set(LLAMA_CONNECT OFF)
set(LLAMA_SUBPROCESS OFF)
set(LLAMA_OPENSSL OFF)
set(MTMD_VIDEO OFF)

include(FetchContent)
FetchContent_Declare(
    llama_cpp
    GIT_REPOSITORY https://github.com/ggml-org/llama.cpp.git
    GIT_TAG f3586e66bc916d672773d4a6505513ba91a3595c
)
FetchContent_MakeAvailable(llama_cpp)

add_executable(OrangeOCRHelper OrangeOCRHelper.cpp)
# NOTE: upstream forbids linking mtmd into llama-common; link both explicitly.
target_link_libraries(OrangeOCRHelper PRIVATE llama-common mtmd)
target_include_directories(OrangeOCRHelper PRIVATE
    ${llama_cpp_SOURCE_DIR}/common
    ${llama_cpp_SOURCE_DIR}/tools/mtmd
    ${llama_cpp_SOURCE_DIR}/vendor
)

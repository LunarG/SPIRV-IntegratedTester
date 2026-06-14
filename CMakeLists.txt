cmake_minimum_required(VERSION 3.28)
project(SPIRV-IntegratedTester LANGUAGES CXX)
enable_testing()

# Require C++17.
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED TRUE)

# Require python3.
find_package(Python3 3.9 COMPONENTS Interpreter REQUIRED)

include(FetchContent)

# ---------------------------------------------------------------------------
# effcee and transitive dependencies (required — used to build FileCheck).
# ---------------------------------------------------------------------------
FetchContent_Declare(
    abseil
    GIT_REPOSITORY https://github.com/abseil/abseil-cpp.git
    GIT_TAG 20260107.1
)
FetchContent_Declare(
    re2
    GIT_REPOSITORY https://github.com/google/re2.git
    GIT_TAG 2025-11-05
)
FetchContent_Declare(
    effcee
    GIT_REPOSITORY https://github.com/google/effcee.git
    GIT_TAG main
)
set(ABSL_ENABLE_INSTALL  ON  CACHE INTERNAL "Enable Abseil install")
set(RE2_BUILD_TESTING    OFF CACHE INTERNAL "Disable re2 tests")
set(EFFCEE_BUILD_TESTING OFF CACHE INTERNAL "Disable effcee tests")
set(EFFCEE_BUILD_SAMPLES OFF CACHE INTERNAL "Disable effcee samples")
FetchContent_MakeAvailable(abseil re2 effcee)

# ---------------------------------------------------------------------------
# Slang
#
# Resolution priority:
#   1. SPIRV_TESTER_SLANG_PATH  — user-specified directory, always wins
#   2. FetchContent             — if SPIRV_TESTER_FETCH_SLANG is ON (default)
#   3. find_program             — system PATH, last resort
# ---------------------------------------------------------------------------
set(SPIRV_TESTER_SLANG_PATH "" CACHE PATH
    "Path to a local slang installation directory (bin/slangc[.exe] must exist inside).")
option(SPIRV_TESTER_FETCH_SLANG
    "Fetch slang via FetchContent if not found via SPIRV_TESTER_SLANG_PATH"
    ON)

if(SPIRV_TESTER_SLANG_PATH)
    # User explicitly pointed us at a slang installation — use it, skip everything else.
    if(WIN32)
        set(SLANG_EXE "${SPIRV_TESTER_SLANG_PATH}/bin/slangc.exe")
    else()
        set(SLANG_EXE "${SPIRV_TESTER_SLANG_PATH}/bin/slangc")
    endif()
    if(NOT EXISTS "${SLANG_EXE}")
        message(FATAL_ERROR
            "SPIRV_TESTER_SLANG_PATH is set to '${SPIRV_TESTER_SLANG_PATH}' "
            "but no slang executable was found at '${SLANG_EXE}'.")
    endif()
    message(STATUS "Using user-provided slang: ${SLANG_EXE}")

elseif(SPIRV_TESTER_FETCH_SLANG)
    # Fetch a known-good slang release.
    set(SLANG_VERSION "2026.10.2")
    if(WIN32)
        set(SLANG_ARCHIVE "slang-${SLANG_VERSION}-windows-x86_64.zip")
        set(SLANG_SHA256 "f21fca4ba78bfb366ef3b282b4926e3efca61c2ffd72a482b024c9f8413331d0")
        set(SLANG_EXE_RELATIVE "bin/slangc.exe")
    elseif(APPLE)
        set(SLANG_ARCHIVE "slang-${SLANG_VERSION}-macos-x86_64.tar.gz")
        set(SLANG_SHA256 "b3722f8108005aaada183915e961881c412c2f43118edb70d5c97a260a71147d")
        set(SLANG_EXE_RELATIVE "bin/slangc")
    else()
        set(SLANG_ARCHIVE "slang-${SLANG_VERSION}-linux-x86_64.tar.gz")
        set(SLANG_SHA256 "e1993c89fe6eb9fce148672ac2b633af1578e413c41b730be446dd8be251376b")
        set(SLANG_EXE_RELATIVE "bin/slangc")
    endif()
    FetchContent_Declare(
        slang_binary
        URL "https://github.com/shader-slang/slang/releases/download/v${SLANG_VERSION}/${SLANG_ARCHIVE}"
        URL_HASH SHA256=${SLANG_SHA256}
    )
    FetchContent_MakeAvailable(slang_binary)
    set(SLANG_EXE "${slang_binary_SOURCE_DIR}/${SLANG_EXE_RELATIVE}")
    message(STATUS "Using FetchContent slang: ${SLANG_EXE}")

else()
    # Fall back to whatever is on the system PATH.
    find_program(SLANG_EXE slangc)
    if(NOT SLANG_EXE)
        message(FATAL_ERROR
            "Could not find slangc. Either:\n"
            "  - Set SPIRV_TESTER_SLANG_PATH to a slang installation directory\n"
            "  - Enable SPIRV_TESTER_FETCH_SLANG to download one automatically\n"
            "  - Ensure slangc is on your system PATH")
    endif()
    message(STATUS "Using system slang: ${SLANG_EXE}")
endif()

# ---------------------------------------------------------------------------
# SPIRV-Tools (spirv-dis, spirv-opt, spirv-val)
#
# Resolution priority:
#   1. SPIRV_TESTER_SPIRV_TOOLS_PATH    — user-specified directory, always wins
#   2. FetchContent (build from source) — if SPIRV_TESTER_FETCH_SPIRV_TOOLS is ON (default)
#   3. find_program                     — system PATH, last resort
# ---------------------------------------------------------------------------
set(SPIRV_TESTER_SPIRV_TOOLS_PATH "" CACHE PATH
    "Path to a SPIRV-Tools installation directory (bin/spirv-dis[.exe] etc. must exist inside).")
option(SPIRV_TESTER_FETCH_SPIRV_TOOLS
    "Fetch and build SPIRV-Tools via FetchContent if not found via SPIRV_TESTER_SPIRV_TOOLS_PATH"
    ON)

if(SPIRV_TESTER_SPIRV_TOOLS_PATH)
    # User explicitly pointed us at a SPIRV-Tools installation — use it, skip everything else.
    if(WIN32)
        set(SPIRV_DIS_EXE "${SPIRV_TESTER_SPIRV_TOOLS_PATH}/bin/spirv-dis.exe")
        set(SPIRV_OPT_EXE "${SPIRV_TESTER_SPIRV_TOOLS_PATH}/bin/spirv-opt.exe")
        set(SPIRV_VAL_EXE "${SPIRV_TESTER_SPIRV_TOOLS_PATH}/bin/spirv-val.exe")
    else()
        set(SPIRV_DIS_EXE "${SPIRV_TESTER_SPIRV_TOOLS_PATH}/bin/spirv-dis")
        set(SPIRV_OPT_EXE "${SPIRV_TESTER_SPIRV_TOOLS_PATH}/bin/spirv-opt")
        set(SPIRV_VAL_EXE "${SPIRV_TESTER_SPIRV_TOOLS_PATH}/bin/spirv-val")
    endif()
    foreach(_tool SPIRV_DIS_EXE SPIRV_OPT_EXE SPIRV_VAL_EXE)
        if(NOT EXISTS "${${_tool}}")
            message(FATAL_ERROR
                "SPIRV_TESTER_SPIRV_TOOLS_PATH is set to '${SPIRV_TESTER_SPIRV_TOOLS_PATH}' "
                "but '${${_tool}}' was not found.")
        endif()
    endforeach()
    message(STATUS "Using user-provided SPIRV-Tools: ${SPIRV_TESTER_SPIRV_TOOLS_PATH}")

elseif(SPIRV_TESTER_FETCH_SPIRV_TOOLS)
    # Build SPIRV-Tools from source. SPIRV-Headers must be populated first
    # so that SPIRV-Tools' CMake can find it.
    set(SPIRV_HEADERS_TAG "ad9184e76a66b1001c29db9b0a3e87f646c64de0")
    set(SPIRV_TOOLS_TAG   "v2026.2")

    set(SPIRV_HEADERS_SKIP_EXAMPLES ON  CACHE INTERNAL "")
    set(SPIRV_HEADERS_SKIP_INSTALL  ON  CACHE INTERNAL "")
    set(SPIRV_SKIP_TESTS            ON  CACHE INTERNAL "Disable SPIRV-Tools tests")
    set(SPIRV_SKIP_EXECUTABLES      OFF CACHE INTERNAL "We need the executables")

    FetchContent_Declare(
        spirv-headers
        GIT_REPOSITORY https://github.com/KhronosGroup/SPIRV-Headers.git
        GIT_TAG        ${SPIRV_HEADERS_TAG}
    )
    FetchContent_Declare(
        spirv-tools
        GIT_REPOSITORY https://github.com/KhronosGroup/SPIRV-Tools.git
        GIT_TAG        ${SPIRV_TOOLS_TAG}
    )
    # Populate headers first so SPIRV-Tools finds them during its configure.
    FetchContent_MakeAvailable(spirv-headers spirv-tools)

    set(SPIRV_DIS_EXE "$<TARGET_FILE:spirv-dis>")
    set(SPIRV_OPT_EXE "$<TARGET_FILE:spirv-opt>")
    set(SPIRV_VAL_EXE "$<TARGET_FILE:spirv-val>")
    message(STATUS "Using FetchContent SPIRV-Tools ${SPIRV_TOOLS_TAG}")

else()
    # Fall back to whatever is on the system PATH.
    find_program(SPIRV_DIS_EXE spirv-dis)
    find_program(SPIRV_OPT_EXE spirv-opt)
    find_program(SPIRV_VAL_EXE spirv-val)
    if(NOT SPIRV_DIS_EXE OR NOT SPIRV_OPT_EXE OR NOT SPIRV_VAL_EXE)
        message(FATAL_ERROR
            "Could not find SPIRV-Tools (spirv-dis, spirv-opt, spirv-val). Either:\n"
            "  - Set SPIRV_TESTER_SPIRV_TOOLS_PATH to a SPIRV-Tools installation directory\n"
            "  - Enable SPIRV_TESTER_FETCH_SPIRV_TOOLS to build one automatically\n"
            "  - Ensure spirv-dis, spirv-opt, and spirv-val are on your system PATH")
    endif()
    message(STATUS "Using system SPIRV-Tools: ${SPIRV_DIS_EXE}")
endif()

# todo:
# ---------------------------------------------------------------------------
# Optional tools: glslang, dxc
# ---------------------------------------------------------------------------
find_program(GLSLANG_EXE glslang)
if(GLSLANG_EXE)
    message(STATUS "Found glslang: ${GLSLANG_EXE}")
else()
    message(STATUS "glslang not found — GLSL tests will not run")
    set(GLSLANG_EXE "")
endif()

find_program(DXC_EXE dxc)
if(DXC_EXE)
    message(STATUS "Found dxc: ${DXC_EXE}")
else()
    message(STATUS "dxc not found — HLSL tests will not run")
    set(DXC_EXE "")
endif()

# ---------------------------------------------------------------------------
# FileCheck (built from effcee)
# ---------------------------------------------------------------------------
add_subdirectory(FileCheck)

# ---------------------------------------------------------------------------
# Generate sit.cfg.py into the build directory.
# FileCheck executable is in the build tree after add_subdirectory(FileCheck).
# ---------------------------------------------------------------------------
set(FILECHECK_EXE "${CMAKE_BINARY_DIR}/FileCheck/FileCheck")

# Two steps: configure_file handles @VAR@ substitutions at configure time,
# file(GENERATE) resolves $<TARGET_FILE:...> expressions at build time.
configure_file(sit.cfg.py.in sit.cfg.py.intermediate @ONLY)
file(GENERATE
    OUTPUT "${CMAKE_BINARY_DIR}/sit.cfg.py"
    INPUT  "${CMAKE_BINARY_DIR}/sit.cfg.py.intermediate"
)

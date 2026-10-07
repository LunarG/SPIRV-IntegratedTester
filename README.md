# SPIR-V Integrated Tester

A regression test suite for [NonSemantic.Shader.DebugInfo](https://github.com/KhronosGroup/SPIRV-Guide/blob/main/chapters/shader_debug_info.md).

[Information about adding tests](./ADD_TEST.md)

## Background

Shader debug information goes through three layers of the ecosystem. All three layers must work together:

1. Shading language compilers (slang, glslang, dxc) emit correct debug information.
2. SPIR-V transforms (spirv-opt) keep the debug information.
3. Debugging tools (RenderDoc, NSight, Validation Layers) read and show the debug information correctly.

This project is a file-based regression suite. It finds errors in each of these layers.

## Building

```sh
cmake -B build
cmake --build build
```

CMake gets and builds [effcee](https://github.com/google/effcee) and [SPIRV-Tools](https://github.com/KhronosGroup/SPIRV-Tools). These two are required. CMake also finds as many of [slang](https://github.com/shader-slang/slang), [glslang](https://github.com/KhronosGroup/glslang/), and [dxc](https://github.com/microsoft/directxshadercompiler) as it can. It uses FetchContent or your system `PATH`.

The test harness is one Python script, `spirv_tester.py`. It reads the paths of the tools from `build/sit.cfg.json`, which CMake generates.

### Shader compilers are optional, but you need at least one

Each of slang, glslang, and dxc is optional. If CMake cannot find a compiler, CMake configure gives a warning and continues. At run time, the harness skips each test that needs a missing compiler. A `SKIP` message gives the reason.

You need **at least one** of the three compilers to run tests. If CMake finds none of them, configure gives a warning, and the harness skips every test.

CMake looks for each compiler in this order:

1. The local path that you set.
2. A pinned release, through FetchContent, if FetchContent is enabled for that compiler.
3. Your system `PATH`.

Microsoft publishes official dxc binaries only for Windows and Linux (x86_64). There is no official macOS binary. On macOS, CMake always looks for dxc on your `PATH`, and `SPIRV_TESTER_FETCH_DXC` has no effect.

### Optional CMake variables

| Variable | Description |
|---|---|
| `SPIRV_TESTER_SLANG_PATH` | Path to a local slang installation (skips FetchContent) |
| `SPIRV_TESTER_FETCH_SLANG` | Set to `OFF` to disable FetchContent for slang (default: `ON`) |
| `SPIRV_TESTER_GLSLANG_PATH` | Path to a local glslang installation (skips FetchContent) |
| `SPIRV_TESTER_FETCH_GLSLANG` | Set to `OFF` to disable FetchContent for glslang (default: `ON`) |
| `SPIRV_TESTER_DXC_PATH` | Path to a local dxc installation (skips FetchContent) |
| `SPIRV_TESTER_FETCH_DXC` | Set to `OFF` to disable FetchContent for dxc (default: `ON`, no effect on macOS) |
| `SPIRV_TESTER_SPIRV_TOOLS_PATH` | Path to a local SPIRV-Tools installation (skips FetchContent) |
| `SPIRV_TESTER_FETCH_SPIRV_TOOLS` | Set to `OFF` to disable FetchContent for SPIRV-Tools (default: `ON`) |

## Running Tests

To run all tests:

```sh
python3 spirv_tester.py
```

To run one test:

```sh
python3 spirv_tester.py tests/slang/example.slang
```

To use a specified configuration file:

```sh
python3 spirv_tester.py --config build/sit.cfg.json
```

### Inspecting failures

When a test fails, the harness copies the intermediate `.spv` and `.spvasm` files to `debug_dir`. You set `debug_dir` in `sit.cfg.json`. The default is `sit-debug/` in the repository root. The failure message gives the full path.

The harness clears this folder at the start of each run. If no test has an unexpected result, the harness removes the folder at the end of the run.

A test with an `// XFAIL:` directive does not copy files, because its failure is expected. See [Documenting a known defect](./ADD_TEST.md#documenting-a-known-defect-the--xfail-directive). To see the SPIR-V of such a test, run its `RUN:` pipeline manually. Alternatively, remove the `XFAIL:` line for one run.

## License

Apache License, Version 2.0. See [LICENSE](LICENSE) for the full text.

Source files have the Apache header. Test shaders in `tests/` do not.

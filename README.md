# SPIR-V Integrated Tester

A regression testing framework for [NonSemantic.Shader.DebugInfo](https://github.com/KhronosGroup/SPIRV-Guide/blob/main/chapters/shader_debug_info.md).

[Information about adding tests](./ADD_TEST.md)

## Background

Shader debug information spans three layers of the ecosystem that must all work together:

1. Shading languages (slang, glslang, dxc) generate correct debug information.
2. SPIR-V modifications (spirv-opt) preserve debug information.
3. Debugging tools (RenderDoc, NSight, Validation Layers) correctly parse and display it.

This framework provides a simple, file-based regression suite to catch breakage across these layers.

## Building

```sh
cmake -B build
cmake --build build
```

This will automatically fetch and build [effcee](https://github.com/google/effcee) and [SPIRV-Tools](https://github.com/KhronosGroup/SPIRV-Tools), which are hard requirements, plus whichever of [slang](https://github.com/shader-slang/slang), [glslang](https://github.com/KhronosGroup/glslang/), and [dxc](https://github.com/microsoft/directxshadercompiler) it can via FetchContent or your system `PATH`.

The test runner is a single Python script, `spirv_tester.py`. It reads the paths of the built and fetched tools from `build/sit.cfg.json`, which CMake generates.

### Shader compilers are optional, but you need at least one

slang, glslang, and dxc are each individually optional. CMake configure will only warn, not fail, if any (or all) of them can't be found. If a compiler can't be found, tests that need it are skipped (not failed) at run time, with a `SKIP` message explaining why.

That said, you do need **at least one** of the three for any tests to actually run. If none are found, configure prints a warning to that effect and every test will be skipped.

Each compiler resolves in the same priority order: an explicit local path, then FetchContent of a pinned release (if enabled), then your system `PATH`. Note that Microsoft only publishes official dxc binaries for Windows and Linux (x86_64); there's no official macOS build, so on macOS dxc always falls through to the `PATH` search regardless of `SPIRV_TESTER_FETCH_DXC`.

### Optional CMake variables

| Variable | Description |
|---|---|
| `SPIRV_TESTER_SLANG_PATH` | Path to a local slang installation (skips FetchContent) |
| `SPIRV_TESTER_FETCH_SLANG` | Set to `OFF` to disable FetchContent for slang (default: `ON`) |
| `SPIRV_TESTER_GLSLANG_PATH` | Path to a local glslang installation (skips FetchContent) |
| `SPIRV_TESTER_FETCH_GLSLANG` | Set to `OFF` to disable FetchContent for glslang (default: `ON`) |
| `SPIRV_TESTER_DXC_PATH` | Path to a local dxc installation (skips FetchContent) |
| `SPIRV_TESTER_FETCH_DXC` | Set to `OFF` to disable FetchContent for dxc (default: `ON`; no effect on macOS) |
| `SPIRV_TESTER_SPIRV_TOOLS_PATH` | Path to a local SPIRV-Tools installation (skips FetchContent) |
| `SPIRV_TESTER_FETCH_SPIRV_TOOLS` | Set to `OFF` to disable FetchContent for SPIRV-Tools (default: `ON`) |

## Running Tests

```sh
python3 spirv_tester.py
```

To run a single test:

```sh
python3 spirv_tester.py tests/slang/example.slang
```

To use an explicit config file:

```sh
python3 spirv_tester.py --config build/sit.cfg.json
```

### Inspecting failures

When a test fails, intermediate `.spv` and `.spvasm` artifacts are automatically saved to the `debug_dir` specified in `sit.cfg.json` (default: `sit-debug/` in the repo root). The failure message will print the exact path. The folder is cleared at the start of each run and removed once no unexpected results remain.

A test that carries an `// XFAIL:` directive saves no artifacts, because that outcome is already understood. See [Documenting a known defect](./ADD_TEST.md#documenting-a-known-defect-the--xfail-directive). To inspect the SPIR-V for one, run its `RUN:` pipeline by hand, or comment out the `XFAIL:` line temporarily.

## License

Apache License, Version 2.0. See [LICENSE](LICENSE) for the full text.

Source files carry the Apache header. Test shaders in `tests/` do not.

# SPIR-V Integrated Tester

A regression testing framework for NonSemantic.ShaderDebugInfo.

## Background

Shader debug information spans three layers of the ecosystem that must all work together:

1. Shading languages (slang, glslang, dxc) generate correct debug information.
2. SPIR-V modifications (spirv-opt) preserve debug information.
3. Debugging tools (RenderDoc, NSight, VVL) correctly parse and display it.

This framework provides a simple, file-based regression suite to catch breakage across these layers.

## Building

```sh
cmake -B build
cmake --build build
```

This will automatically fetch and build the required dependencies (slang, SPIRV-Tools, effcee).

### Optional CMake variables

| Variable | Description |
|---|---|
| `SPIRV_TESTER_SLANG_PATH` | Path to a local slang installation (skips FetchContent) |
| `SPIRV_TESTER_FETCH_SLANG` | Set to `OFF` to disable FetchContent for slang (default: `ON`) |
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

When a test fails, intermediate `.spv` and `.spvasm` artifacts are automatically saved to the `debug_dir` specified in `sit.cfg.json` (default: `sit-debug/` in the repo root). The failure message will print the exact path. The folder is cleared at the start of each run and removed entirely when all tests pass.

## Adding Tests

Adding a test is as simple as dropping a shader file into the appropriate subdirectory:

```
tests/
  slang/      — Slang shaders
  glsl/       — GLSL shaders
  hlsl/       — HLSL shaders
  internal/   — Harness self-tests (verbose and permutation RUN lines)
```

Each test file is self-contained. A `// RUN:` line defines the compilation pipeline and a series of `// CHECK:` lines define the SPIR-V patterns to verify. No registration or build system changes are needed — the harness discovers test files automatically.

The harness is smart about the `// RUN:` line — you only need to specify the compiler. The target, source file, debug flag, SPIR-V output, disassembly, and check steps are all handled automatically. For example, with slangc:

```slang
// RUN: %slangc
```

If you need full control over the pipeline, you can use `RUN_OVERRIDE:` instead. This skips all smart pipeline logic and runs the command exactly as written after substitution:

```slang
// RUN_OVERRIDE: %slangc %s -target spirv -stage compute -g -o %spv && %spirv_dis %spv -o %spvasm && %check --spvasm %spvasm --source %s
```

`RUN:` and `RUN_OVERRIDE:` are mutually exclusive — a test file may only contain one or the other, not both.

The `tests/internal/` directory contains tests that exercise various RUN line permutations and are used to regression test the harness itself.

### Available substitutions

| Substitution | Description |
|---|---|
| `%s` | The test file path |
| `%spv` | Output path for the compiled SPIR-V binary |
| `%spvasm` | Output path for the disassembled SPIR-V text |
| `%slangc` | Path to the slangc executable |
| `%spirv_dis` | Path to the spirv-dis executable |
| `%spirv_opt` | Path to the spirv-opt executable |
| `%spirv_val` | Path to the spirv-val executable |
| `%check` | Path to the FileCheck executable |
| `%glslang` | Path to glslang (if found) |
| `%dxc` | Path to dxc (if found) |

## License

TBD

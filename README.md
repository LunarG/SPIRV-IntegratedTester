# SPIR-V Integrated Tester

A regression testing framework for [NonSemantic.ShaderDebugInfo](https://github.com/KhronosGroup/SPIRV-Guide/blob/main/chapters/shader_debug_info.md).

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

This testing framework is just a python, but by default, will use the `build/sit.cfg.json` to load the path to these various tools being build/fetched.

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

### Design principle: the harness never guesses stage or profile

Auto-injected defaults are stage-agnostic or fail loudly if wrong. Anything that actually selects a stage or profile (`-S <stage>`, `-T <profile>`) stays explicit, chosen by the test author via the compiler's own mechanisms.

### glslang: naming a file `<name>.<stage>.glsl` skips `-S <stage>`

glslang can infer the shader stage from the file name itself, e.g. `example.comp.glsl` is recognized as a compute shader with no `-S comp` needed. Name a `.glsl` test with the compound `<stage>.glsl` suffix (`vert`, `frag`, `comp`, etc.) and the RUN line can drop the stage flag entirely, matching slang's minimal style. A plain `.glsl` file with no stage anywhere (neither in the name nor an explicit `-S`) fails loudly at compile time rather than guessing, so this is safe to rely on.

glslang also recognizes the bare `.<stage>` suffix on its own, with no `.glsl` at all (`example.comp`, `example.frag`, etc.), and the harness's default suffix list includes all of glslang's stage names for exactly this reason.

If you'd rather not rename the file, `-S <stage>` explicitly still works exactly as before.

### dxc: entry point defaults to `main`

dxc itself defaults its entry-point search to a function literally named `main`, and fails to compile (rather than silently compiling something else) if no such function exists. The harness relies on this: `-E main` is injected automatically, so an HLSL test with an entry function named `main` doesn't need to specify it. If your entry function has a different name, add `-E <name>` explicitly.

The `tests/internal/` directory contains tests that exercise various RUN line permutations and are used to regression test the harness itself.

### Available substitutions

| Substitution | Description |
|---|---|
| `%s` | The test file path |
| `%spv` | Output path for the compiled SPIR-V binary |
| `%spvasm` | Output path for the disassembled SPIR-V text |
| `%slangc` | Path to slangc (if found) |
| `%spirv_dis` | Path to the spirv-dis executable |
| `%spirv_opt` | Path to the spirv-opt executable |
| `%spirv_val` | Path to the spirv-val executable |
| `%check` | Path to the FileCheck executable |
| `%glslang` | Path to glslang (if found) |
| `%dxc` | Path to dxc (if found) |

## License

TBD

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

To keep intermediate `.spv` and `.spvasm` files for inspection:

```sh
python3 spirv_tester.py --tmp-dir /tmp/sit-debug
```

To use an explicit config file:

```sh
python3 spirv_tester.py --config build/sit.cfg.json
```

## Adding Tests

Adding a test is as simple as dropping a shader file into the appropriate subdirectory:

```
tests/
  slang/   — Slang shaders
  glsl/    — GLSL shaders
  hlsl/    — HLSL shaders
```

Each test file is self-contained. A `// RUN:` line defines the compilation pipeline and a series of `// CHECK:` lines define the SPIR-V patterns to verify. No registration or build system changes are needed — the harness discovers test files automatically.

Here is a minimal Slang example:

```slang
// RUN: %slangc %s -target spirv -stage compute -g -o %spv && %spirv_dis %spv -o %spvasm && %check --spvasm %spvasm --source %s

// CHECK: [[DATA_STR:%[0-9]+]] = OpString "data"
// CHECK: [[DATA_MEMBER:%[0-9]+]] = OpExtInst {{.*}} DebugTypeMember [[DATA_STR]]

struct SSBO {
    float4 data;
};

[[vk::binding(1, 0)]]
RWStructuredBuffer<SSBO> ssbo;

[shader("compute")]
[numthreads(1, 1, 1)]
void main() {
    ssbo[0].data = float4(0.0);
}
```

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

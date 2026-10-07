# Adding Tests

See [README.md](./README.md) for how to build and run the tests.

To add a test, put a shader file into the correct directory:

```
tests/
  slang/      Slang shaders
  glsl/       GLSL shaders
  hlsl/       HLSL shaders
  internal/   Harness self-tests (verbose and permutation RUN lines)
```

The harness finds test files automatically. You do not register a test or change the build system.

Each test file contains all that the test needs. A `// RUN:` line gives the compile pipeline. One or more `// CHECK:` lines give the SPIR-V patterns that the test asserts.

In a `// RUN:` line, you name only the compiler. The harness adds the target, the source file, the debug flag, the SPIR-V output, the disassembly step, and the assertion step. For example, with slangc:

```slang
// RUN: %slangc
```

For full control of the pipeline, use `RUN_OVERRIDE:` instead. The harness then adds nothing. It applies the substitutions and runs the command as written:

```slang
// RUN_OVERRIDE: %slangc %s -target spirv -stage compute -g -o %spv && %spirv_dis %spv -o %spvasm && %check --spvasm %spvasm --source %s
```

A test file contains one `RUN:` line or one `RUN_OVERRIDE:` line, not both.

## Design principle: the harness never guesses stage or profile

Each default that the harness adds does not depend on the shader stage, or it fails with a clear error if it is wrong. The test author selects the stage or profile (`-S <stage>`, `-T <profile>`) explicitly, with the flags of the compiler.

## glslang: naming a file `<name>.<stage>.glsl` skips `-S <stage>`

glslang can get the shader stage from the file name. For example, glslang compiles `example.comp.glsl` as a compute shader without `-S comp`. Use a `.<stage>.glsl` suffix, such as `.vert.glsl`, `.frag.glsl`, or `.comp.glsl`. Then the `RUN:` line does not need the stage flag.

This method is safe. A `.glsl` file without a stage in its name or an explicit `-S` fails at compile time. glslang does not guess the stage.

glslang also accepts the stage suffix alone, without `.glsl`, such as `example.comp` or `example.frag`. For this reason, the default suffix list of the harness includes all the stage names of glslang.

If you do not want to rename the file, `-S <stage>` continues to work.

## dxc: entry point defaults to `main`

By default, dxc looks for an entry function with the name `main`. If no such function exists, dxc fails to compile. dxc does not compile a different function. The harness adds `-E main`, so an HLSL test with an entry function named `main` does not need `-E`. If your entry function has a different name, add `-E <name>`.

## Available substitutions

| Substitution | Description |
|---|---|
| `%s` | The test file path |
| `%spv` | Output path for the compiled SPIR-V binary |
| `%spvasm` | Output path for the disassembled SPIR-V text |
| `%t` | Path prefix for other temporary files of the test (for example, `%t.opt.spv`) |
| `%slangc` | Path to slangc (if found) |
| `%spirv_dis` | Path to the spirv-dis executable |
| `%spirv_opt` | Path to the spirv-opt executable |
| `%spirv_val` | Path to the spirv-val executable |
| `%check` | Path to the FileCheck executable |
| `%glslang` | Path to glslang (if found) |
| `%dxc` | Path to dxc (if found) |

## Documenting a known defect: the `// XFAIL:` directive

A test can document a defect that is not fixed yet. Such a test has one `// XFAIL: <reason>` line:

```slang
// RUN: %slangc
// XFAIL: SPIRV-Tools#6718, DebugValue references OpUndef after spirv-opt
```

The `<reason>` is required. A URL in the reason is optional. The directive applies to the whole file. A file can have only one `XFAIL:` line, as with `RUN:`.

**The `CHECK:` lines assert the output that the tooling must emit, not the output that it emits today.** Thus the test fails, and the reason tells why the correct output is missing. When the defect is fixed upstream, the test starts to pass. You do not need to change the test.

### How results are reported

| Status | Meaning | Effect on the suite |
|---|---|---|
| `XFAIL` | A test with the directive failed, as expected | Not a failure. Exit code stays 0 |
| `XPASS` | A test with the directive passed | **A failure.** Exit code is non-zero |

For an expected failure, the harness prints one line with the reason. Thus the defect is visible on each run:

```
XFAIL tests/slang/inout_scalar.slang (SPIRV-Tools#6718, DebugValue references OpUndef after spirv-opt)
```

To see the full effcee diagnostic, run with `-v`. The harness does not copy files to `debug_dir` for an expected failure.

An unexpected pass is the purpose of the directive. It has one of two causes. Find the cause before you change the test:

1. The defect was fixed upstream. Remove the `XFAIL:` line.
2. A `CHECK:` line became less strict until it matched. Restore the line.

### Before you write one

An `XFAIL` test asserts output that does not exist yet. Thus the test can demand a change that the tooling must not make. `NonSemantic.Shader.DebugInfo.100` instructions are non-semantic. They must never change the semantic instructions of a module. To report the conditions that each assertion must meet, run `python3 check_debug_operands.py <test>`.

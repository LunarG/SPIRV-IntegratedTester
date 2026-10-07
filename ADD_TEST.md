# Adding Tests

See [README.md](./README.md) for how to build and run the tests.

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

## Design principle: the harness never guesses stage or profile

Auto-injected defaults are stage-agnostic or fail loudly if wrong. Anything that actually selects a stage or profile (`-S <stage>`, `-T <profile>`) stays explicit, chosen by the test author via the compiler's own mechanisms.

## glslang: naming a file `<name>.<stage>.glsl` skips `-S <stage>`

glslang can infer the shader stage from the file name itself, e.g. `example.comp.glsl` is recognized as a compute shader with no `-S comp` needed. Name a `.glsl` test with the compound `<stage>.glsl` suffix (`vert`, `frag`, `comp`, etc.) and the RUN line can drop the stage flag entirely, matching slang's minimal style. A plain `.glsl` file with no stage anywhere (neither in the name nor an explicit `-S`) fails loudly at compile time rather than guessing, so this is safe to rely on.

glslang also recognizes the bare `.<stage>` suffix on its own, with no `.glsl` at all (`example.comp`, `example.frag`, etc.), and the harness's default suffix list includes all of glslang's stage names for exactly this reason.

If you'd rather not rename the file, `-S <stage>` explicitly still works exactly as before.

## dxc: entry point defaults to `main`

dxc itself defaults its entry-point search to a function literally named `main`, and fails to compile (rather than silently compiling something else) if no such function exists. The harness relies on this: `-E main` is injected automatically, so an HLSL test with an entry function named `main` doesn't need to specify it. If your entry function has a different name, add `-E <name>` explicitly.

## Available substitutions

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

## Documenting a known defect: the `// XFAIL:` directive

Some tests document a defect that is not fixed yet. Those tests carry one `// XFAIL: <reason>` line:

```slang
// RUN: %slangc
// XFAIL: SPIRV-Tools#6718, DebugValue references OpUndef after spirv-opt
```

The `<reason>` is required. A URL inside the reason is optional. The directive is file-level, and only one is supported per file, as with `RUN:`.

**The `CHECK:` lines still assert what the tooling must emit, not what it emits today.** So the test genuinely fails, and the reason records why the correct output does not appear yet. This polarity is deliberate: when the defect is fixed upstream, the test starts passing on its own and needs no rewrite.

### How results are reported

| Status | Meaning | Effect on the suite |
|---|---|---|
| `XFAIL` | A test with the directive failed, as expected | Not a failure. Exit code stays 0 |
| `XPASS` | A test with the directive passed | **A failure.** Exit code is non-zero |

An expected failure prints one line naming the reason, so the defect stays visible on every run:

```
XFAIL tests/slang/inout_scalar.slang (SPIRV-Tools#6718, DebugValue references OpUndef after spirv-opt)
```

Run with `-v` to see the full effcee diagnostic instead. Artifacts are not copied to `debug_dir` for an expected failure.

An unexpected pass is the payoff of the directive. It means one of two things, and you need to find out which before you act:

1. The defect was fixed upstream. Remove the `XFAIL:` line.
2. A `CHECK:` line was weakened until it matched. Restore it.

### Before you write one

An `XFAIL` test asserts output that does not exist yet, so it can accidentally demand something the tooling is not permitted to do. `NonSemantic.Shader.DebugInfo.100` instructions are non-semantic and must never change the semantic instructions of a module. Run `python3 check_debug_operands.py <test>` to report the conditions an assertion must satisfy.

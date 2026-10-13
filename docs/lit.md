# Running the suite with lit

This is a prototype of running the SPIR-V Integrated Tester on top of
[lit](https://pypi.org/project/lit/), the LLVM Integrated Tester. lit already
does what `spirv_tester.py` does by hand: it finds the tests, reads `RUN:` lines,
applies substitutions, runs the commands, handles `XFAIL`, skips tests whose tools
are missing, and reports the results. You don't need to know LLVM to use it.
lit is a standalone, pure-Python package, and every extension point is ordinary
Python.

Current state of the prototype:

- **All 82 existing tests run under lit with no edits**, with the same results as
  `spirv_tester.py`. lit reports 84, because it also runs the two stock-lit
  examples in `tests/plain_lit/`.
- **About 2 s instead of 15 s.** lit runs the tests in parallel.
- **`spirv_tester.py` and `sit.cfg.json` are unchanged** and still work, so both
  runners can be compared side by side.

- [Quick start](#quick-start)
- [Part 1: Using lit in this repo](#part-1-using-lit-in-this-repo)
- [Part 2: Extending lit](#part-2-extending-lit)
- [Rerunning when things build](#rerunning-when-things-build)
- [Differences from spirv\_tester.py](#differences-from-spirv_testerpy)
- [Gotchas](#gotchas)
- [Where things live](#where-things-live)

## Quick start

```sh
cmake -B build                       # also fetches lit; nothing to pip install
cmake --build build

build/sit-lit.py -sv tests                         # whole suite
build/sit-lit.py -v tests/slang/example.slang      # one test, by its source path
build/sit-lit.py -v tests/hlsl                     # one directory
build/sit-lit.py -sv --filter=inline tests         # tests whose name matches a regex

ninja -C build check-sit                           # rebuild tools, then run the suite
LIT_OPTS="--filter=glsl" ninja -C build check-sit  # same, with extra lit options
ctest --test-dir build                             # the suite as one CTest test

build/sit-lit.py --watch -sv tests                 # rerun on every change (see below)
build/sit-lit.py --param spirv_tools_dir=$HOME/SPIRV-Tools/build/tools -sv tests
```

Useful lit options are `-v` (show failure output), `-a` (show all output), `-s`
(progress bar), `--show-unsupported`, `--show-xfail`, `-j N`,
`--xunit-xml-output=FILE` (JUnit XML for CI), and `--time-tests`.
`build/sit-lit.py --help` lists them all.

## Part 1: Using lit in this repo

### What lit already does

| Built into lit | Replaces this in `spirv_tester.py` |
|---|---|
| Finds tests by `config.suffixes` under a root directory | `discover_tests`, `"suffixes"` |
| `RUN:` lines, run by lit's internal shell (`&&`, `\|`, redirects; the same on Windows) | `_parse_run_lines`, `_run_command` |
| `config.substitutions`, plus built-ins: `%s` (the test file), `%S` (its directory), `%t` (a temp path for this test) | `_apply_substitutions`, `"substitutions"` |
| `REQUIRES:` / `UNSUPPORTED:`, checked against `config.available_features` | `_missing_compiler` |
| `XFAIL:`. An unexpected pass counts as a failure | `_parse_xfail`, `_print_xpass` |
| Temp files kept under `<build>/tests/<dir>/Output/` | `debug_dir`, `_save_debug_artifacts` |
| Parallel runs, `--filter`, JUnit XML, timing, retries | `parse_args` and the reporting code |
| Runs the tests that failed last time first | (nothing) |

### The pieces

A lit suite is a directory with a config file in it. This repo uses the same
layout as LLVM and libcxx.

```
tests/lit.cfg.py               checked in: name, suffixes, test format, substitutions
tests/lit.site.cfg.py.in       template; CMake fills in this build's tool paths
tests/<dir>/lit.local.cfg      optional: changes the config for one directory
utils/sit/                     Python package with the custom code (Part 2)
utils/sit-lit.py.in            template for build/sit-lit.py, the entry point

build/tests/lit.site.cfg.py    generated; sets the tool paths, then loads tests/lit.cfg.py
build/sit-lit.py               generated; runs lit for this build directory
```

**`lit.site.cfg.py`** holds only what differs between build directories. CMake
writes it with `configure_file` + `file(GENERATE)`, the same two steps as
`sit.cfg.json`, because the SPIRV-Tools paths are `$<TARGET_FILE:...>`
expressions:

```python
config.sit_src_root = r"/path/to/SPIRV-IntegratedTester"
config.sit_obj_root = r"/path/to/SPIRV-IntegratedTester/build"
config.sit_tools = {
    "slangc":    r".../slangc",
    "spirv_dis": r".../spirv-dis",
    # ...
}
lit_config.load_config(config, r"/path/to/SPIRV-IntegratedTester/tests/lit.cfg.py")
```

**`lit.cfg.py`** sets up everything else. A stripped-down version, using only
stock lit, would be:

```python
import lit.formats

config.name = "SPIRV-IntegratedTester"
config.test_format = lit.formats.ShTest(execute_external=False)
config.suffixes = [".slang", ".glsl", ".hlsl", ".comp", ...]
config.test_source_root = os.path.join(config.sit_src_root, "tests")
config.test_exec_root = os.path.join(config.sit_obj_root, "tests")   # where Output/ goes

for name, path in config.sit_tools.items():
    if path:
        config.available_features.add(name)           # for "REQUIRES: slangc"
        config.substitutions.append((f"%{name}", path))
```

The real file adds one line to that: it hands the work to `utils/sit/config.py`,
which also installs the custom test format from Part 2.

**`sit-lit.py`** follows the pattern of LLVM's `llvm-lit`. It puts the fetched
lit on `sys.path` and calls `lit.main.main()` with a `config_map` parameter that
maps `tests/lit.cfg.py` to `build/tests/lit.site.cfg.py`. Because of that map,
lit accepts test paths in the source tree (`tests/slang/example.slang`) as well as
in the build tree, and always gets the right tool paths. Running a pip-installed
`lit build/tests` works too.

**CMake** fetches the lit source archive from PyPI (`SPIRV_TESTER_FETCH_LIT`, on by
default), in the same way the compilers are fetched. lit has no dependencies, so
putting the archive on `sys.path` is enough. With the option off, CMake checks
that `Python3_EXECUTABLE` can `import lit`. It also adds the `check-sit` target
and a CTest test.

### What a test looks like in stock lit

`tests/plain_lit/` holds two tests written for lit's stock `ShTest` format. Its
`lit.local.cfg` switches that one directory back to `ShTest`:

```c
// REQUIRES: glslang
// RUN: %glslang -V --quiet -gVS -S comp %s -o %t.spv
// RUN: %spirv_val %t.spv
// RUN: %spirv_dis %t.spv -o %t.spvasm
// RUN: %check --spvasm %t.spvasm --source %s

// CHECK: [[DATA_STR:%[0-9]+]] = OpString "data"
...
```

Each step is spelled out, one `RUN:` per line. `%t` gives each test its own temp
files, and `REQUIRES:` uses the tool features from `lit.cfg.py`. lit also
supports `DEFINE:` for substitutions that only one file sees (see
`slang_store.test`). These files use a `.test` suffix so that `spirv_tester.py`
ignores them. The compilers are told the language with a flag (`-S comp`,
`-lang slang`) instead of the file extension.

If the suite ever moves fully to stock lit, every test would look like this, and
`utils/sit/format.py` and `pipeline.py` could be deleted. Until then, the custom
format below keeps the short RUN lines working.

## Part 2: Extending lit

lit has no plugin registry. Its config files are Python, run with `config` and
`lit_config` in scope, so a config can import your own package and install your
own classes. libcxx does exactly this: its `lit.cfg.py` imports
[`libcxx/utils/libcxx/test/`](https://github.com/llvm/llvm-project/tree/main/libcxx/utils/libcxx/test).
This repo follows the same pattern with `utils/sit/`.

The extension points below are listed from least to most code.

### 1. Config-time Python: features, substitutions, `--param`

Anything that can be computed in Python goes in the config. This prototype uses
the config for:

- **Tool features.** Each tool that was found becomes a lit feature, so a test can
  say `REQUIRES: dxc` and a missing compiler makes it UNSUPPORTED.
- **Per-test output names.** `%spv` → `%t.spv` and `%spvasm` → `%t.spvasm`. lit
  then expands `%t`.
- **Overrides with `--param`.** `lit_config.params` holds every
  `--param NAME=VALUE` from the command line. `utils/sit/tools.py` uses it to
  replace tool paths for one run, without a reconfigure:

  ```sh
  build/sit-lit.py --param spirv_tools_dir=~/SPIRV-Tools/build/tools -sv tests  # all 3 SPIRV-Tools
  build/sit-lit.py --param spirv_opt=/tmp/my-spirv-opt -sv tests               # one tool
  build/sit-lit.py --param slangc=/opt/slang/bin/slangc -sv tests
  ```

  lit prints a note for each overridden path, and stops with an error if the
  path doesn't exist.

The config could also, for example, run `slangc -v` and add a
`slang-2026.10` feature, or read `--param opt_level=...` and change a
substitution.

### 2. `lit.local.cfg`: per-directory changes

lit runs a `lit.local.cfg` in each directory, on a copy of the parent config.
`tests/plain_lit/lit.local.cfg` uses one to change the test format and suffixes.
The same mechanism can mark a whole directory unsupported:

```python
if "dxc" not in config.available_features:
    config.unsupported = True
```

### 3. Custom keywords: `IntegratedTestKeywordParser`

lit's parser accepts extra keywords. Each one is an
`IntegratedTestKeywordParser(keyword, kind, parser=None)`, where `kind` is a
`ParserKind`: `TAG`, `COMMAND`, `LIST`, `BOOLEAN_EXPR`, `INTEGER`, `CUSTOM`,
and a few others. libcxx adds `ADDITIONAL_COMPILE_FLAGS:` and
`FILE_DEPENDENCIES:` this way. `utils/sit/format.py` uses it for:

- `RUN_OVERRIDE:` (a `CUSTOM` parser that keeps the text and line number).
- `RUN:`, which is parsed with a `CUSTOM` parser of its own so that the short form
  can be expanded.
- `XFAIL:` with a free-text reason. lit's own `XFAIL:` is a `BOOLEAN_EXPR` over
  features, so `SPIRV-Tools#6718, DebugValue references ...` would be a syntax
  error there.
- `REQUIRES:` / `UNSUPPORTED:`, which reuse lit's own `BOOLEAN_EXPR` parser.

### 4. A custom test format: `SpirvTest`

A test format decides what one test file means. It is a class with two jobs:

- `getTestsForPath` / `getTestsInDirectory`: turn files into tests. The format
  inherits this from `FileBasedTest`, which yields one test per file that matches
  `config.suffixes`.
- `execute(test, lit_config)`: run one test and return a `lit.Test.Result`.

`SpirvTest` subclasses `lit.formats.ShTest` and overrides `execute()`:

1. **Parse.** It collects the directives above. A malformed directive makes this
   one test UNRESOLVED.
2. **Check requirements.** It adds an implicit `REQUIRES:` for every tool the RUN
   line names, then applies lit's `REQUIRES:` / `UNSUPPORTED:` rules.
3. **Expand.** It turns `RUN:` into the full compile → (opt) → disassemble → check
   pipeline. `utils/sit/pipeline.py` is the logic from `spirv_tester.py`,
   unchanged.
4. **Run.** It hands the command back to lit: `getDefaultSubstitutions`,
   `applySubstitutions`, then `_runShTest`, the same calls `ShTest` makes.
5. **Report.** On a failure, it puts the `spirv_tester.py`-style header (RUN line,
   tool paths, artifacts, the comment block around the failed CHECK) in front of
   lit's own output.

For an `XFAIL:` test it sets `test.xfails = ["*"]`, and lit converts FAIL→XFAIL
and PASS→XPASS after `execute()` returns.

A failure looks like this (paths shortened):

```
FAIL: SPIRV-IntegratedTester :: slang/example.slang (60 of 82)
******************** TEST 'SPIRV-IntegratedTester :: slang/example.slang' FAILED ********************
RUN line : %slangc -g -target spirv %s -o %spv && %spirv_dis %spv -o %spvasm && %check --spvasm %spvasm --source %s
Paths    :
  %slangc    = .../slang_binary-src/bin/slangc
  %spirv_dis = .../spirv-tools-build/tools/spirv-dis
  %check     = .../FileCheck/FileCheck
Artifacts: .../build/tests/slang/Output/example.slang.tmp.*
Context  :
      12 | // The store goes through two chained access chains into the buffer.
      13 | // CHECK: [[PTR1:%[0-9]+]] = OpAccessChain {{.*}} %ssbo
  --> 14 | // CHECK-NEXT: [[PTR2:%[0-9]+]] = OpUntypedAccessChainKHR {{.*}} [[PTR1]]
      15 | // CHECK-NEXT: OpStore [[PTR2]]

Exit Code: 1

Command Output (stdout):
--
# RUN: at line 1
...
# executed command: .../FileCheck --spvasm .../example.slang.tmp.spvasm --source .../example.slang
# .---command stderr------------
# | .../example.slang:14:16: error: expected string not found in input
...
```

**Stability.** `parseIntegratedTestScriptCommands`, `IntegratedTestKeywordParser`,
`getTempPaths`, `getDefaultSubstitutions`, `applySubstitutions` and
`buildPdbgCommand` are public names in `lit.TestRunner`. `_runShTest` is not, but
libcxx's format calls it too. None of these is a promised API, so the lit version
is pinned in `CMakeLists.txt` (`LIT_VERSION`). Run the suite after bumping it.

Some things a format can do that this one doesn't yet:

- **Several tests from one file.** Override `getTestsForPath` to yield one test
  per compiler or per optimization level from a single shader, e.g.
  `foo.slang:O0` and `foo.slang:O2`.
- **Always validate.** Insert `%spirv_val %spv` into every expanded pipeline.
- **Different reporting.** Anything can go into `Result.output`, and a `Result`
  can also carry metrics (`result.addMetric`), which lit writes to its JSON
  output (`-o FILE`).

### 5. Outside lit: the entry point and the build

Some features are better placed around lit than inside it:

- **`sit-lit.py`** is ours, so it can take options lit doesn't have. It handles
  `--watch` itself (below) and passes everything else to lit.
- **CMake** decides what to rebuild before a run (`check-sit`).
- **`LIT_OPTS`** is an environment variable that lit reads as extra
  command-line options, which is how options reach `ninja check-sit`.

## Rerunning when things build

There are two ways, and they work together.

**`ninja check-sit`.** The target depends on `FileCheck` and, when SPIRV-Tools is
fetched, on `spirv-dis`/`spirv-opt`/`spirv-val`. Ninja rebuilds whatever is out of
date, then runs the suite. This is the usual LLVM `check-*` pattern.

**`sit-lit.py --watch [lit options] tests`** runs the suite, then polls for
changes and reruns:

| What changed | What reruns |
|---|---|
| A test file under `tests/` | Only the changed tests (passed to lit as `--filter`) |
| A tool binary: a rebuild of FileCheck or SPIRV-Tools, or a tool given with `--param` | Everything |
| `utils/sit/*`, a `lit.cfg.py` / `lit.local.cfg`, or `lit.site.cfg.py` (a reconfigure) | Everything |

It waits until files stop changing for a second before it runs, so a build that
writes several files triggers one run. Each run is a fresh process, so changes to
the harness itself take effect. Combined with `--param`, this gives a quick loop
for SPIRV-Tools work: rebuild `spirv-opt` in your own checkout, and the suite
reruns against it.

```sh
build/sit-lit.py --watch --param spirv_tools_dir=~/SPIRV-Tools/build/tools -s tests
```

It polls modification times using only the Python standard library, so it
needs no extra tools and works the same on every platform. lit also runs the
tests that failed last time first, so the failure you are working on shows up
first.

## Differences from spirv_tester.py

| | `spirv_tester.py` | lit prototype |
|---|---|---|
| Speed | Serial, about 15 s | Parallel, about 2 s |
| Artifacts | Copied to `sit-debug/` for failures; the folder is cleared each run | Always kept in `build/tests/<dir>/Output/<test>.tmp.*`; overwritten on the next run |
| Missing compiler | `SKIP` | `UNSUPPORTED` (listed with `--show-unsupported`) |
| No RUN line | `SKIP` with a warning | `UNSUPPORTED` |
| Malformed directive | Stops the whole run | That one test is `UNRESOLVED`; the rest still run |
| XFAIL reason | Printed on every run | In the test's output (`-v` for a failure; `--show-xfail` lists them) |
| Shell | The system shell (`shell=True`) | lit's internal shell, the same on every platform |
| Environment | Inherited | lit passes only a fixed set of variables (PATH, LD_LIBRARY_PATH, ...). Add more with `config.environment` |

## Gotchas

- **lit finds a directive anywhere in a line, comments included.** A comment such
  as `// ... DEFINE: makes a substitution` is parsed as a `DEFINE:` directive, and
  the test is UNRESOLVED. Don't put a keyword followed by a colon in prose.
  `spirv_tester.py` only matched directives at the start of a `//` comment, so
  this is new. No existing test is affected.
- **Substitutions are regular expressions, tried in list order.** A short pattern
  matches inside a longer one (`%spv` inside `%spvasm`), so `utils/sit/config.py`
  sorts them longest first. lit's built-ins (`%s`, `%t`, …) come after the config's
  own, which is why `%slangc` isn't eaten by `%s`. Braced names such as `%{slangc}`
  avoid prefix clashes entirely.
- **Tests run in their `Output/` directory**, not the directory lit was started
  in. Relative paths in `--param` values are made absolute for this reason.
- **lit versions.** PyPI went from 18.1.8 (2024) to 23.1.0 (August 2026) with
  nothing in between. lit 23 deprecates `execute_external=True`; the prototype
  uses the internal shell. The pinned version is in `CMakeLists.txt`.
- **`tests/lit.cfg.py` alone is not runnable.** Run through `build/sit-lit.py` or
  point lit at `build/tests`. Plain `lit tests/...` stops with a message that says
  so.

## Where things live

| `spirv_tester.py` | lit prototype |
|---|---|
| `DEFAULT_SUFFIXES`, `load_config`, `discover_tests` | `utils/sit/config.py`, lit |
| `_inject_*`, `_build_pipeline` | `utils/sit/pipeline.py` (copied unchanged) |
| `_parse_run_lines`, `_parse_xfail`, `run_test` | `utils/sit/format.py` (`SpirvTest`) |
| `_missing_compiler` | Tool features in `config.py`, plus the implicit `REQUIRES:` in `format.py` |
| `_apply_substitutions`, `_run_command` | lit |
| `_failure_context`, `_print_failure` | `utils/sit/report.py` |
| `main()`, the summary | lit |
| `sit.cfg.json` | `build/tests/lit.site.cfg.py` |
| (none) | `utils/sit/tools.py` (`--param`), `utils/sit/watch.py` (`--watch`) |

### Not done yet

- **Windows and macOS are untested.** `sit-lit.py` is a Python script. On Windows,
  run it with `python build\sit-lit.py`. CMake also passes it through
  `Python3_EXECUTABLE` for `check-sit` and CTest.
- **`pipeline.py` duplicates the logic in `spirv_tester.py`.** That is deliberate
  while both runners exist. Once lit is adopted, `spirv_tester.py`,
  `sit.cfg.json.in` and the `sit.cfg.json` generation in CMake can be removed.
- **Moving to stock lit** (Part 1) would mean rewriting every RUN line in the
  `plain_lit/` style and changing `XFAIL: <reason>` to `XFAIL: *` with the reason
  in a comment. After that, `format.py` and `pipeline.py` go away.

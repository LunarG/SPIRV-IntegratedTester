#!/usr/bin/env python3
"""
SPIR-V Integrated Tester
A simple test harness for NonSemantic.ShaderDebugInfo regression testing.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import textwrap
from pathlib import Path


# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

# Extensions the harness will treat as test files if not specified in config.
DEFAULT_SUFFIXES = [".glsl", ".hlsl", ".slang", ".spvasm"]

# Substitutions the harness requires to be defined in the config.
REQUIRED_SUBSTITUTIONS = ["%spirv_dis", "%check"]

# Compiler substitutions that take a source file as their next argument.
COMPILER_SUBSTITUTIONS = ["%slangc", "%glslang", "%dxc"]

# Debug flags per compiler. Injected automatically if not already present.
COMPILER_DEBUG_FLAGS = {
    "%slangc":  "-g",
    "%glslang": "-g",
    "%dxc":     "-Zi",
}

# Default targets per compiler. Injected automatically if no -target flag is present.
COMPILER_DEFAULT_TARGETS = {
    "%slangc": "-target spirv",
}

# Pipeline stage classifications.
STAGE_COMPILE     = "compile"
STAGE_DISASSEMBLE = "disassemble"
STAGE_CHECK       = "check"
STAGE_UNKNOWN     = "unknown"

# Default config file name to search for.
DEFAULT_CONFIG_NAME = "sit.cfg.json"


class Config:
    def __init__(self):
        self.test_dir: str = ""
        self.debug_dir: str = ""
        self.suffixes: list[str] = list(DEFAULT_SUFFIXES)
        # List of (pattern, replacement) tuples, e.g. ("%slangc", "/usr/bin/slangc").
        self.substitutions: list[tuple[str, str]] = []


def find_default_config() -> Path | None:
    """Search for sit.cfg.json in the current directory then build/."""
    for candidate in [
        Path.cwd() / DEFAULT_CONFIG_NAME,
        Path.cwd() / "build" / DEFAULT_CONFIG_NAME,
    ]:
        if candidate.is_file():
            return candidate
    return None


def load_config(cfg_path: Path) -> Config:
    """Load and validate a sit.cfg.json file."""
    try:
        raw = json.loads(cfg_path.read_text(encoding="utf-8"))
    except OSError as e:
        _die(f"Cannot read config file: {e}")
    except json.JSONDecodeError as e:
        _die(f"Invalid JSON in config file {cfg_path}:\n  {e}")

    config = Config()

    config.test_dir  = raw.get("test_dir", str(cfg_path.parent))
    config.debug_dir = raw.get("debug_dir", "")
    config.suffixes  = raw.get("suffixes", DEFAULT_SUFFIXES)

    # Build substitutions list, skipping empty values (optional tools not found).
    subs = raw.get("substitutions", {})
    config.substitutions = [
        (pattern, replacement)
        for pattern, replacement in subs.items()
        if replacement
    ]

    _validate_config(config, cfg_path)
    return config


def _validate_config(config: Config, cfg_path: Path) -> None:
    """Check that all required substitutions are defined."""
    defined = {pat for pat, _ in config.substitutions}
    missing = [r for r in REQUIRED_SUBSTITUTIONS if r not in defined]
    if missing:
        _die(
            f"Config {cfg_path} is missing required substitutions: "
            + ", ".join(missing)
        )


# ---------------------------------------------------------------------------
# Test discovery
# ---------------------------------------------------------------------------

def discover_tests(config: Config) -> list[Path]:
    """Return all test files under config.test_dir matching config.suffixes."""
    test_root = Path(config.test_dir)
    if not test_root.is_dir():
        _die(f"test_dir does not exist: {test_root}")

    suffixes = set(config.suffixes)
    tests = sorted(
        p for p in test_root.rglob("*") if p.is_file() and p.suffix in suffixes
    )
    return tests


# ---------------------------------------------------------------------------
# Test execution
# ---------------------------------------------------------------------------

RUN_RE          = re.compile(r"^//\s*RUN:\s*(.+)$")
RUN_OVERRIDE_RE = re.compile(r"^//\s*RUN_OVERRIDE:\s*(.+)$")


def _inject_implicit_source(run_line: str) -> str:
    """If a RUN line contains a known compiler substitution but %s does not
    already follow it, inject %s immediately after the compiler substitution.
    """
    for compiler in COMPILER_SUBSTITUTIONS:
        if compiler in run_line:
            if not re.search(rf"{re.escape(compiler)}\s+%s", run_line):
                return run_line.replace(compiler, f"{compiler} %s", 1)
    return run_line


def _inject_debug_flag(run_line: str) -> str:
    """If a RUN line contains a known compiler substitution but no debug flag,
    inject the appropriate debug flag immediately after the compiler substitution.
    """
    for compiler, flag in COMPILER_DEBUG_FLAGS.items():
        if compiler in run_line and flag not in run_line:
            return run_line.replace(compiler, f"{compiler} {flag}", 1)
    return run_line


def _inject_default_target(run_line: str) -> str:
    """If a RUN line contains a compiler with a known default target and no
    -target flag is present, inject the default target after the compiler.
    """
    for compiler, target in COMPILER_DEFAULT_TARGETS.items():
        if compiler in run_line and "-target" not in run_line:
            return run_line.replace(compiler, f"{compiler} {target}", 1)
    return run_line


def _classify_segment(segment: str) -> str:
    """Classify a pipeline segment by its stage."""
    for compiler in COMPILER_SUBSTITUTIONS:
        if compiler in segment:
            return STAGE_COMPILE
    if "%spirv_dis" in segment:
        return STAGE_DISASSEMBLE
    if "%check" in segment:
        return STAGE_CHECK
    return STAGE_UNKNOWN


def _split_pipeline(run_line: str) -> list[tuple[str, str]]:
    """Split a RUN line on && and classify each segment.
    Returns a list of (stage, segment) tuples.
    """
    segments = [s.strip() for s in run_line.split("&&")]
    return [(_classify_segment(s), s) for s in segments if s]


def _build_pipeline(run_line: str, test_file: Path) -> str:
    """Split the RUN line into pipeline stages, fill in any missing stages,
    and reassemble into a full shell command.
    """
    stages = _split_pipeline(run_line)
    stage_map = {stage: cmd for stage, cmd in stages}

    # Compile stage must be present.
    if STAGE_COMPILE not in stage_map:
        _die(f"{test_file}: RUN: line has no compile stage (expected %slangc, %glslang, or %dxc).")

    # Build the ordered pipeline.
    pipeline = []

    # Compile stage — always first. Inject -o %spv if missing.
    compile_cmd = stage_map[STAGE_COMPILE]
    if "%spv" not in compile_cmd:
        compile_cmd = f"{compile_cmd} -o %spv"
    pipeline.append(compile_cmd)

    # Unknown pass-through stages (e.g. %spirv_opt) — preserve in order.
    for stage, cmd in stages:
        if stage == STAGE_UNKNOWN:
            pipeline.append(cmd)

    # Disassemble stage — use default if missing.
    if STAGE_DISASSEMBLE in stage_map:
        pipeline.append(stage_map[STAGE_DISASSEMBLE])
    else:
        pipeline.append("%spirv_dis %spv -o %spvasm")

    # Check stage — use default if missing.
    if STAGE_CHECK in stage_map:
        pipeline.append(stage_map[STAGE_CHECK])
    else:
        pipeline.append("%check --spvasm %spvasm --source %s")

    return " && ".join(pipeline)


def _parse_run_lines(test_file: Path) -> tuple[list[str], list[str]]:
    """Extract all '// RUN:' and '// RUN_OVERRIDE:' lines from a test file.
    Returns (run_lines, override_lines).
    """
    run_lines = []
    override_lines = []
    try:
        for line in test_file.read_text(encoding="utf-8").splitlines():
            stripped = line.strip()
            m = RUN_RE.match(stripped)
            if m:
                run_lines.append(m.group(1).strip())
                continue
            m = RUN_OVERRIDE_RE.match(stripped)
            if m:
                override_lines.append(m.group(1).strip())
    except OSError as e:
        _die(f"Cannot read test file {test_file}: {e}")
    return run_lines, override_lines


def _apply_substitutions(
    command: str,
    substitutions: list[tuple[str, str]],
    extra: dict[str, str],
) -> str:
    """Replace all substitution patterns in a RUN line.
    Sorted longest-first to prevent shorter patterns (e.g. %s, %spv) from
    matching inside longer ones (e.g. %spvasm, %spv).
    """
    all_subs = list(substitutions) + list(extra.items())
    all_subs.sort(key=lambda pair: len(pair[0]), reverse=True)
    for pattern, replacement in all_subs:
        command = command.replace(pattern, replacement)
    return command


def run_test(test_file: Path, config: Config, tmp_dir: Path) -> bool:
    """
    Run all RUN: lines in a single test file.
    Returns True if the test passed, False otherwise.
    """
    run_lines, override_lines = _parse_run_lines(test_file)

    # Mutual exclusivity check.
    if run_lines and override_lines:
        _die(f"{test_file}: cannot mix RUN: and RUN_OVERRIDE: in the same file.")

    if not run_lines and not override_lines:
        _warn(f"SKIP  {test_file} (no RUN: or RUN_OVERRIDE: lines found)")
        return True  # Not a failure; just nothing to run.

    # Per-test substitutions available to RUN: and RUN_OVERRIDE: lines.
    stem = test_file.stem
    spv_out = tmp_dir / f"{stem}.spv"
    spvasm_out = tmp_dir / f"{stem}.spvasm"

    extra_subs = {
        "%s":      str(test_file),       # the test file itself
        "%spv":    str(spv_out),         # compiled SPIR-V binary
        "%spvasm": str(spvasm_out),      # disassembled SPIR-V text
        "%t":      str(tmp_dir / stem),  # generic temp file prefix
    }

    if run_lines:
        if len(run_lines) > 1:
            _die(f"{test_file}: multiple RUN: lines found. Only one RUN: line is supported per test.")
        run_line = run_lines[0]
        run_line = _inject_implicit_source(run_line)
        run_line = _inject_default_target(run_line)
        run_line = _inject_debug_flag(run_line)
        run_line = _build_pipeline(run_line, test_file)
    else:
        if len(override_lines) > 1:
            _die(f"{test_file}: multiple RUN_OVERRIDE: lines found. Only one RUN_OVERRIDE: line is supported per test.")
        # RUN_OVERRIDE: skip all smart pipeline logic, just substitute and run.
        run_line = override_lines[0]

    cmd = _apply_substitutions(run_line, config.substitutions, extra_subs)
    success, output = _run_command(cmd)
    if not success:
        debug_path = _save_debug_artifacts(test_file, tmp_dir, config)
        _print_failure(test_file, run_line, cmd, output, debug_path)
        return False

    return True


def _save_debug_artifacts(
    test_file: Path, tmp_dir: Path, config: Config
) -> Path | None:
    """Copy temp artifacts for a failed test into debug_dir. Returns the path."""
    if not config.debug_dir:
        return None

    debug_dir = Path(config.debug_dir) / test_file.stem
    debug_dir.mkdir(parents=True, exist_ok=True)

    for artifact in tmp_dir.glob(f"{test_file.stem}.*"):
        shutil.copy2(artifact, debug_dir / artifact.name)

    return debug_dir


def _run_command(cmd: str) -> tuple[bool, str]:
    """
    Run a shell command string. Returns (success, combined_output).
    Uses shell=True to match lit behaviour (pipes, &&, etc. work naturally).
    """
    try:
        result = subprocess.run(
            cmd,
            shell=True,  # noqa: S602
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        return result.returncode == 0, result.stdout
    except OSError as e:
        return False, str(e)


def _print_failure(
    test_file: Path, run_line: str, expanded_cmd: str, output: str,
    debug_path: Path | None = None,
) -> None:
    sep = "-" * 70
    print(f"\nFAIL  {test_file}")
    print(sep)
    print(f"  RUN line : {run_line}")
    print(f"  Expanded : {expanded_cmd}")
    if debug_path:
        print(f"  Artifacts: {debug_path}")
    if output.strip():
        print("  Output   :")
        for line in output.splitlines():
            print(f"    {line}")
    print(sep)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="SPIR-V Integrated Tester — ShaderDebugInfo regression harness",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=textwrap.dedent("""\
            Examples:
              %(prog)s
              %(prog)s tests/slang/basic_debug.slang
              %(prog)s --config build/sit.cfg.json
        """),
    )
    parser.add_argument(
        "--config",
        metavar="CFG",
        help=f"Path to sit.cfg.json (default: searches ./ then ./build/).",
    )
    parser.add_argument(
        "tests",
        metavar="TEST",
        nargs="*",
        help="Specific test file(s) to run. If omitted, discovers all tests.",
    )
    parser.add_argument(
        "-v", "--verbose",
        action="store_true",
        help="Print PASS results as well as failures.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    # Resolve config path.
    if args.config:
        cfg_path = Path(args.config).resolve()
        if not cfg_path.is_file():
            _die(f"Config file not found: {cfg_path}")
    else:
        cfg_path = find_default_config()
        if cfg_path is None:
            _die(
                f"No config file found. Searched for '{DEFAULT_CONFIG_NAME}' in "
                f"'./' and './build/'. Use --config to specify one explicitly."
            )

    config = load_config(cfg_path)

    # Resolve test list.
    if args.tests:
        test_files = [Path(t).resolve() for t in args.tests]
        for t in test_files:
            if not t.is_file():
                _die(f"Test file not found: {t}")
    else:
        test_files = discover_tests(config)
        if not test_files:
            _warn("No test files found.")
            return 0

    # Clear debug_dir at the start of each run.
    if config.debug_dir:
        debug_dir = Path(config.debug_dir)
        if debug_dir.exists():
            shutil.rmtree(debug_dir)

    # Run tests.
    passed = 0
    failed = 0

    with tempfile.TemporaryDirectory(prefix="sit_") as tmp:
        tmp_dir = Path(tmp)
        for test_file in test_files:
            ok = run_test(test_file, config, tmp_dir)
            if ok:
                passed += 1
                if args.verbose:
                    print(f"PASS  {test_file}")
            else:
                failed += 1

    # Clear debug_dir if everything passed.
    if failed == 0 and config.debug_dir:
        debug_dir = Path(config.debug_dir)
        if debug_dir.exists():
            shutil.rmtree(debug_dir)

    # Summary.
    total = passed + failed
    print(f"\n{'=' * 70}")
    print(f"Results: {passed}/{total} passed", end="")
    if failed:
        print(f", {failed} FAILED")
    else:
        print()
    print("=" * 70)

    return 0 if failed == 0 else 1


def _die(msg: str) -> None:
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(1)


def _warn(msg: str) -> None:
    print(f"warning: {msg}", file=sys.stderr)


if __name__ == "__main__":
    sys.exit(main())

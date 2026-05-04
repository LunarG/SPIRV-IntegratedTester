#!/usr/bin/env python3
"""
SPIR-V Integrated Tester
A simple test harness for NonSemantic.ShaderDebugInfo regression testing.
"""
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
import tempfile
import textwrap
import types
from pathlib import Path


# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

# Extensions the harness will treat as test files if config.suffixes is unset.
DEFAULT_SUFFIXES = [".glsl", ".hlsl", ".slang", ".spvasm"]

# Substitutions the harness requires to be defined in the config.
REQUIRED_SUBSTITUTIONS = ["%spirv_dis", "%check"]


class Config:
    """
    Object injected into the cfg file as `config`.
    The cfg file populates its attributes; the harness reads them back.
    """

    def __init__(self, cfg_path: Path):
        self.name: str = ""
        self.test_dir: str = str(cfg_path.parent)  # default: same dir as cfg
        self.suffixes: list[str] = list(DEFAULT_SUFFIXES)
        # List of (pattern, replacement) tuples, e.g. ("%glslang", "/usr/bin/glslang").
        self.substitutions: list[tuple[str, str]] = []
        # Optional: tmp dir for .spv / .spvasm intermediates.
        # Defaults to a system temp dir created at runtime.
        self.tmp_dir: str = ""


def load_config(cfg_path: Path) -> Config:
    """
    exec() the Python cfg file and return the populated Config object.
    Raises SystemExit with a clear message on any error.
    """
    config = Config(cfg_path)
    global_ns = {"config": config, "os": os, "sys": sys}

    try:
        source = cfg_path.read_text(encoding="utf-8")
    except OSError as e:
        _die(f"Cannot read config file: {e}")

    try:
        exec(compile(source, str(cfg_path), "exec"), global_ns)  # noqa: S102
    except Exception as e:
        _die(f"Error in config file {cfg_path}:\n  {type(e).__name__}: {e}")

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

RUN_RE = re.compile(r"^//\s*RUN:\s*(.+)$")


def _parse_run_lines(test_file: Path) -> list[str]:
    """Extract all '// RUN: ...' lines from a test file."""
    run_lines = []
    try:
        for line in test_file.read_text(encoding="utf-8").splitlines():
            m = RUN_RE.match(line.strip())
            if m:
                run_lines.append(m.group(1).strip())
    except OSError as e:
        _die(f"Cannot read test file {test_file}: {e}")
    return run_lines


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
    run_lines = _parse_run_lines(test_file)
    if not run_lines:
        _warn(f"SKIP  {test_file} (no RUN: lines found)")
        return True  # Not a failure; just nothing to run.

    # Per-test substitutions available to every RUN: line.
    stem = test_file.stem
    spv_out = tmp_dir / f"{stem}.spv"
    spvasm_out = tmp_dir / f"{stem}.spvasm"

    extra_subs = {
        "%s": str(test_file),           # the test file itself (matches lit convention)
        "%spv": str(spv_out),           # compiled SPIR-V binary
        "%spvasm": str(spvasm_out),     # disassembled SPIR-V text
        "%t": str(tmp_dir / stem),      # generic temp file prefix
    }

    for run_line in run_lines:
        cmd = _apply_substitutions(run_line, config.substitutions, extra_subs)
        success, output = _run_command(cmd)
        if not success:
            _print_failure(test_file, run_line, cmd, output)
            return False

    return True


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
    test_file: Path, run_line: str, expanded_cmd: str, output: str
) -> None:
    sep = "-" * 70
    print(f"\nFAIL  {test_file}")
    print(sep)
    print(f"  RUN line : {run_line}")
    print(f"  Expanded : {expanded_cmd}")
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
              %(prog)s lit.cfg.py
              %(prog)s lit.cfg.py tests/glsl/basic_debug.glsl
              %(prog)s lit.cfg.py --test-dir tests/glsl
        """),
    )
    parser.add_argument("config", metavar="CFG", help="Path to the lit.cfg.py file")
    parser.add_argument(
        "tests",
        metavar="TEST",
        nargs="*",
        help="Specific test file(s) to run. If omitted, discovers all tests.",
    )
    parser.add_argument(
        "--test-dir",
        metavar="DIR",
        help="Override config.test_dir for test discovery.",
    )
    parser.add_argument(
        "--tmp-dir",
        metavar="DIR",
        help="Directory for intermediate .spv/.spvasm files (default: system temp).",
    )
    parser.add_argument(
        "-v", "--verbose",
        action="store_true",
        help="Print PASS results as well as failures.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    cfg_path = Path(args.config).resolve()
    if not cfg_path.is_file():
        _die(f"Config file not found: {cfg_path}")

    config = load_config(cfg_path)

    if args.test_dir:
        config.test_dir = args.test_dir

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

    # Set up temp directory.
    if args.tmp_dir:
        tmp_dir = Path(args.tmp_dir)
        tmp_dir.mkdir(parents=True, exist_ok=True)
        tmp_ctx = None
    elif config.tmp_dir:
        tmp_dir = Path(config.tmp_dir)
        tmp_dir.mkdir(parents=True, exist_ok=True)
        tmp_ctx = None
    else:
        tmp_ctx = tempfile.TemporaryDirectory(prefix="spirv_tester_")
        tmp_dir = Path(tmp_ctx.name)

    # Run tests.
    passed = 0
    failed = 0

    try:
        for test_file in test_files:
            ok = run_test(test_file, config, tmp_dir)
            if ok:
                passed += 1
                if args.verbose:
                    print(f"PASS  {test_file}")
            else:
                failed += 1
    finally:
        if tmp_ctx is not None:
            tmp_ctx.cleanup()

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

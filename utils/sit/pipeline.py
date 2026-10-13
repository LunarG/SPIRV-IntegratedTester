# Copyright (c) 2026 LunarG, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Expands a terse RUN: line into the full compile/disassemble/check pipeline.

This is the RUN: line logic from spirv_tester.py, moved here unchanged except
that an error raises PipelineError instead of exiting, because it now runs
inside a lit worker. The expansion works on the RUN: line before lit applies
substitutions, so it still sees %slangc, %spv and so on.

    // RUN: %slangc -O0
becomes
    %slangc -g -target spirv %s -O0 -o %spv && %spirv_dis %spv -o %spvasm
        && %check --spvasm %spvasm --source %s
"""
from __future__ import annotations

import re

# Compiler substitutions that take a source file as their next argument.
COMPILER_SUBSTITUTIONS = ["%slangc", "%glslang", "%dxc"]

# Debug flags per compiler. Injected automatically if not already present.
# dxc note: -Zi alone only emits legacy debug info, not the
# NonSemantic.Shader.DebugInfo.100 instructions this harness tests.
COMPILER_DEBUG_FLAGS = {
    "%slangc":  "-g",
    "%glslang": "-gVS",
    "%dxc":     "-Zi -fspv-debug=vulkan-with-source",
}

# Default flags injected per compiler if not already present, as lists of
# (existence_check, flag) pairs. Only flags safe to assume go here.
COMPILER_DEFAULT_TARGETS = {
    "%slangc":  [("-target", "-target spirv")],
    # glslang prints the name of each input file to stdout. --quiet stops
    # that line, but glslang still prints compile errors.
    "%glslang": [("-V", "-V"), ("--quiet", "--quiet")],
    "%dxc":     [("-spirv", "-spirv"), ("-E", "-E main")],
}

# Output-file flags per compiler. Defaults to "-o" if not listed here.
# dxc note: dxc has no plain -o flag, only -Fo.
COMPILER_OUTPUT_FLAGS = {
    "%dxc": "-Fo",
}

# Pipeline stage classifications.
STAGE_COMPILE     = "compile"
STAGE_DISASSEMBLE = "disassemble"
STAGE_CHECK       = "check"
STAGE_UNKNOWN     = "unknown"


class PipelineError(ValueError):
    """A RUN: line that cannot be expanded. lit reports the test UNRESOLVED."""


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
    """If a RUN line contains a compiler with known default flags, inject
    whichever of those flags aren't already present, immediately after the
    compiler.
    """
    for compiler, defaults in COMPILER_DEFAULT_TARGETS.items():
        if compiler not in run_line:
            continue
        for check, flag in defaults:
            if check not in run_line:
                run_line = run_line.replace(compiler, f"{compiler} {flag}", 1)
        return run_line
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


def _compiler_output_flag(compile_cmd: str) -> str:
    """Return the output-file flag for whichever compiler appears in this
    compile stage. Defaults to "-o" if that compiler isn't listed in
    COMPILER_OUTPUT_FLAGS.
    """
    for compiler in COMPILER_SUBSTITUTIONS:
        if compiler in compile_cmd:
            return COMPILER_OUTPUT_FLAGS.get(compiler, "-o")
    return "-o"


def _build_pipeline(run_line: str) -> str:
    """Split the RUN line into pipeline stages, fill in any missing stages,
    and reassemble into a full shell command.
    """
    stages = _split_pipeline(run_line)
    stage_map = dict(stages)

    # Compile stage must be present.
    if STAGE_COMPILE not in stage_map:
        raise PipelineError(
            "RUN: line has no compile stage (expected %slangc, %glslang, or %dxc).")

    # Build the ordered pipeline.
    pipeline = []

    # Compile stage, always first. Inject the compiler's output flag if missing.
    compile_cmd = stage_map[STAGE_COMPILE]
    if "%spv" not in compile_cmd:
        output_flag = _compiler_output_flag(compile_cmd)
        compile_cmd = f"{compile_cmd} {output_flag} %spv"
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


def expand(run_line: str) -> str:
    """Return the full pipeline for a RUN: line, with substitutions not yet applied."""
    run_line = _inject_implicit_source(run_line)
    run_line = _inject_default_target(run_line)
    run_line = _inject_debug_flag(run_line)
    return _build_pipeline(run_line)

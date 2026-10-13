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

"""SpirvTest, the lit test format for the existing test files.

A lit test format decides what one test file means. lit's stock ShTest runs
each RUN: line as written. SpirvTest keeps the directives these tests already
use, so every test runs under lit without an edit:

    RUN:           terse; expanded into the full pipeline (see pipeline.py)
    RUN_OVERRIDE:  run as written, no expansion
    XFAIL:         free text giving the reason; the test is always expected
                   to fail (lit's own XFAIL: takes feature expressions)
    REQUIRES:      lit's meaning, checked against config.available_features
    UNSUPPORTED:   lit's meaning

A test also implicitly REQUIRES every tool its RUN: line names, so a test for
a compiler that was not found is UNSUPPORTED rather than failing.

Everything after parsing is lit's: it applies the substitutions (%s, %t and
the tool paths), runs the command in its internal shell, and sorts the result
into PASS / FAIL / XFAIL / XPASS / UNSUPPORTED.
"""
from __future__ import annotations

import re
from pathlib import Path

import lit.formats
import lit.Test
import lit.TestRunner
from lit.TestRunner import IntegratedTestKeywordParser, ParserKind

from . import pipeline, report

RUN = "RUN:"
RUN_OVERRIDE = "RUN_OVERRIDE:"
XFAIL = "XFAIL:"
REQUIRES = "REQUIRES:"
UNSUPPORTED = "UNSUPPORTED:"


def _collect(line_number: int, line: str, output: list | None) -> list[tuple[int, str]]:
    """A ParserKind.CUSTOM parser that keeps each directive's text and line."""
    output = output or []
    output.append((line_number, line.strip()))
    return output


def _parse_directives(source_path: str) -> dict[str, list]:
    """Return the value of each directive in the test file.

    RUN:, RUN_OVERRIDE: and XFAIL: map to [(line number, text)]. REQUIRES: and
    UNSUPPORTED: map to lit's list of boolean expressions. A malformed
    expression raises ValueError.
    """
    parsers = [
        IntegratedTestKeywordParser(RUN, ParserKind.CUSTOM, _collect),
        IntegratedTestKeywordParser(RUN_OVERRIDE, ParserKind.CUSTOM, _collect),
        IntegratedTestKeywordParser(XFAIL, ParserKind.CUSTOM, _collect),
        IntegratedTestKeywordParser(REQUIRES, ParserKind.BOOLEAN_EXPR),
        IntegratedTestKeywordParser(UNSUPPORTED, ParserKind.BOOLEAN_EXPR),
    ]
    by_keyword = {p.keyword: p for p in parsers}
    for line_number, keyword, text in lit.TestRunner.parseIntegratedTestScriptCommands(
            source_path, by_keyword.keys()):
        by_keyword[keyword].parseLine(line_number, text)
    return {p.keyword: p.getValue() or [] for p in parsers}


def _directive_error(directives: dict[str, list]) -> str | None:
    """Return why the directives are malformed, or None if they are fine."""
    runs, overrides, xfails = directives[RUN], directives[RUN_OVERRIDE], directives[XFAIL]
    if runs and overrides:
        return "cannot mix RUN: and RUN_OVERRIDE: in the same file."
    if len(runs) > 1 or len(overrides) > 1:
        return "only one RUN: or RUN_OVERRIDE: line is supported per test."
    if len(xfails) > 1:
        return "only one XFAIL: line is supported per test."
    if xfails and not xfails[0][1]:
        return ("XFAIL: requires a reason. For example: "
                "'// XFAIL: SPIRV-Tools#6718, DebugValue references OpUndef'.")
    return None


def _unsupported_reason(test) -> str | None:
    """Return why lit's REQUIRES:/UNSUPPORTED: rules rule the test out, or None."""
    missing = test.getMissingRequiredFeatures()
    if missing:
        return "Test requires the following unavailable features: " + ", ".join(missing)
    unsupported = test.getUnsupportedFeatures()
    if unsupported:
        return "Test does not support the following features: " + ", ".join(unsupported)
    return None


def _used_tool_features(command: str, tools: dict[str, str]) -> list[str]:
    """Return the tool names that a command uses, as lit features."""
    return [name for name in tools
            if re.search(rf"%{re.escape(name)}(?![A-Za-z0-9_])", command)]


class SpirvTest(lit.formats.ShTest):
    """A test file with one RUN: or RUN_OVERRIDE: line, as spirv_tester.py runs it."""

    def __init__(self):
        super().__init__(execute_external=False)

    # pylint: disable-next=invalid-name,too-many-return-statements
    def execute(self, test, litConfig):
        """Run one test. lit calls this from a worker process."""
        if test.config.unsupported:
            return lit.Test.Result(lit.Test.UNSUPPORTED, "Test is unsupported")

        source_path = test.getSourcePath()
        try:
            directives = _parse_directives(source_path)
        except ValueError as e:
            return lit.Test.Result(lit.Test.UNRESOLVED, str(e))

        error = _directive_error(directives)
        if error:
            return lit.Test.Result(lit.Test.UNRESOLVED, error)

        runs, overrides = directives[RUN], directives[RUN_OVERRIDE]
        if not runs and not overrides:
            # spirv_tester.py skips these rather than failing them.
            return lit.Test.Result(lit.Test.UNSUPPORTED, "no RUN: or RUN_OVERRIDE: line found")
        keyword, (line_number, run_line) = (RUN, runs[0]) if runs else (RUN_OVERRIDE, overrides[0])

        xfail_reason = directives[XFAIL][0][1] if directives[XFAIL] else None
        if xfail_reason:
            # "*" is lit's "expected to fail everywhere". lit turns the result
            # into XFAIL or XPASS after this function returns.
            test.xfails.append("*")

        test.requires += directives[REQUIRES] + _used_tool_features(run_line, test.config.sit_tools)
        test.unsupported += directives[UNSUPPORTED]
        reason = _unsupported_reason(test)
        if reason:
            return lit.Test.Result(lit.Test.UNSUPPORTED, reason)

        if keyword == RUN:
            try:
                run_line = pipeline.expand(run_line)
            except pipeline.PipelineError as e:
                return lit.Test.Result(lit.Test.UNRESOLVED, str(e))

        return self._run(test, litConfig, keyword, line_number, run_line, xfail_reason)

    @staticmethod
    def _run(test, lit_config, keyword, line_number, run_line, xfail_reason):
        """Substitute and run the command the same way lit's ShTest does."""
        if lit_config.noExecute:
            return lit.Test.Result(lit.Test.PASS)

        tmp_dir, tmp_base = lit.TestRunner.getTempPaths(test)
        substitutions = lit.TestRunner.getDefaultSubstitutions(test, tmp_dir, tmp_base)
        conditions = {feature: True for feature in test.config.available_features}
        command = lit.TestRunner.buildPdbgCommand(f"{keyword} at line {line_number}", run_line)
        try:
            script = lit.TestRunner.applySubstitutions(
                [command], substitutions, conditions,
                recursion_limit=test.config.recursiveExpansionLimit)
        except ValueError as e:
            return lit.Test.Result(lit.Test.UNRESOLVED, str(e))

        # _runShTest is not public API. libcxx's format calls it too; it is why
        # the lit version is pinned in CMakeLists.txt.
        # pylint: disable-next=protected-access
        result = lit.TestRunner._runShTest(test, lit_config, False, script, tmp_base)

        if result.code == lit.Test.FAIL:
            artifacts = f"{tmp_base}.tmp.*"
            result.output = report.header(Path(test.getSourcePath()), run_line,
                                          test.config.sit_tools, result.output, artifacts,
                                          xfail_reason) + result.output
        elif result.code == lit.Test.PASS and xfail_reason:
            result.output = report.xpass_note(xfail_reason) + result.output
        return result

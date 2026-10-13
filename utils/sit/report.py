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

"""The failure report that SpirvTest puts in front of lit's own output.

lit already prints each command it ran and that command's output. This adds
what spirv_tester.py showed and lit does not: the unexpanded RUN: line, the
path of each tool it used, where the artifacts are, and the comment block
around the CHECK line that failed.
"""
from __future__ import annotations

import re
from pathlib import Path

ENCODING = "utf-8"

# A location in an effcee message, such as "test.slang:16:11: error: ...".
# For a failed CHECK-NOT, the error names the .spvasm file and a note names
# the test file. So both kinds are accepted. lit's internal shell puts "# | "
# in front of every line of command output.
EFFCEE_LOCATION_RE = re.compile(
    r"^(?:# \| )?(?P<path>.+?):(?P<line>\d+):\d+: (?:error|note): ")


def _used_tools(run_line: str, tools: dict[str, str]) -> list[tuple[str, str]]:
    """Return the (substitution, path) pairs that a RUN line uses, in RUN line order.

    The match is longest-first, and each match becomes spaces, so a shorter
    pattern cannot match inside a longer one (a %spirv tool inside %spirv_dis).
    """
    remaining = run_line
    used = []
    for name, path in sorted(tools.items(), key=lambda pair: len(pair[0]), reverse=True):
        pattern = f"%{name}"
        position = remaining.find(pattern)
        if position < 0:
            continue
        used.append((position, pattern, path))
        # Replace each match with filler of the same length. The filler keeps
        # the positions of later matches correct.
        remaining = remaining.replace(pattern, " " * len(pattern))
    return [(pattern, path) for _, pattern, path in sorted(used)]


def failure_context(test_file: Path, output: str) -> tuple[int, list[tuple[int, str]]]:
    """Return the failed directive and the comment block that holds it.

    effcee names the failed directive by its line in the test file. The
    comments above that line usually give the reason for the assertion. This
    function moves up and down from that line until it finds a blank line or
    a line that is not a comment.

    The result is the line number of the failed directive and the block as
    (line number, text) pairs in source order. The block is empty if the
    output names no line in the test file, for example when the compiler
    fails, or if the file cannot be read, so that the report itself never fails.
    """
    target = test_file.resolve()
    failed_line = None
    for line in output.splitlines():
        match = EFFCEE_LOCATION_RE.match(line)
        if match and Path(match.group("path")).resolve() == target:
            failed_line = int(match.group("line"))
            break
    if failed_line is None:
        return 0, []

    try:
        with test_file.open(encoding=ENCODING) as f:
            source = f.read().splitlines()
    except (OSError, UnicodeDecodeError):
        return 0, []
    if not 1 <= failed_line <= len(source):
        return 0, []

    first = failed_line
    while first > 1 and source[first - 2].lstrip().startswith("//"):
        first -= 1
    last = failed_line
    while last < len(source) and source[last].lstrip().startswith("//"):
        last += 1
    return failed_line, [(n, source[n - 1]) for n in range(first, last + 1)]


def header(test_file: Path, run_line: str, tools: dict[str, str], output: str,
           artifacts: str, xfail_reason: str | None) -> str:
    """Return the report that goes in front of lit's output for a failed test."""
    lines = []
    if xfail_reason:
        lines.append(f"XFAIL    : {xfail_reason}")
    lines.append(f"RUN line : {run_line}")
    used = _used_tools(run_line, tools)
    if used:
        lines.append("Paths    :")
        width = max(len(pattern) for pattern, _ in used)
        for pattern, path in used:
            lines.append(f"  {pattern:<{width}} = {path}")
    lines.append(f"Artifacts: {artifacts}")
    failed_line, context = failure_context(test_file, output)
    if context:
        lines.append("Context  :")
        width = len(str(context[-1][0]))
        for number, text in context:
            marker = "-->" if number == failed_line else "   "
            lines.append(f"  {marker} {number:>{width}} | {text}")
    return "\n".join(lines) + "\n\n"


def xpass_note(xfail_reason: str) -> str:
    """Return the note for a test that has an XFAIL: line but passed."""
    return (f"XFAIL    : {xfail_reason}\n"
            "This test passed although it has an XFAIL: line. If the defect is fixed,\n"
            "remove the XFAIL: line. If it is not fixed, a CHECK line has probably\n"
            "been weakened until it matched.\n\n")

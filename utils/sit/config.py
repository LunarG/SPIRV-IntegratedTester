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

"""Suite setup, called from tests/lit.cfg.py."""
from __future__ import annotations

import os

from . import tools as sit_tools
from .format import SpirvTest

# Extensions treated as test files. Includes glslang's bare stage suffixes
# (glslang infers the shader stage directly from these, the same idea as the
# .<stage>.glsl compound suffix).
SUFFIXES = [
    ".glsl", ".hlsl", ".slang", ".spvasm",
    ".vert", ".tesc", ".tese", ".geom", ".frag", ".comp",
    ".mesh", ".task",
    ".rgen", ".rint", ".rahit", ".rchit", ".rmiss", ".rcall",
]


def configure(config, lit_config) -> None:
    """Fill in the lit config for the suite.

    `config` already holds sit_src_root, sit_obj_root and sit_tools from the
    generated lit.site.cfg.py.
    """
    config.name = "SPIRV-IntegratedTester"
    config.test_format = SpirvTest()
    config.suffixes = SUFFIXES
    config.test_source_root = os.path.join(config.sit_src_root, "tests")
    # lit writes each test's %t files under <exec root>/<dir>/Output/.
    config.test_exec_root = os.path.join(config.sit_obj_root, "tests")

    tools, overridden = sit_tools.resolve(config.sit_tools, lit_config.params)
    for name in overridden:
        lit_config.note(f"--param override: %{name} = {tools[name]}")

    substitutions = []
    for name, path in tools.items():
        if not path:
            continue
        if name in overridden and not os.path.isfile(path):
            lit_config.fatal(f"--param {name}: no file at {path}")
        # A tool's name is also a lit feature. A test can say "REQUIRES: dxc",
        # and SpirvTest adds the feature for each tool a RUN: line names.
        config.available_features.add(name)
        substitutions.append((f"%{name}", path))
    # Keeps the tools that were not found, with an empty path, so that a test
    # naming one is UNSUPPORTED rather than running a bare "%dxc".
    config.sit_tools = tools

    if not any(name in config.available_features for name in sit_tools.COMPILERS):
        lit_config.warning("No shader compilers (slang, glslang, dxc) are configured. "
                           "All tests will be UNSUPPORTED.")

    # Per-test outputs. lit expands %t after these, to a path under Output/.
    substitutions += [("%spvasm", "%t.spvasm"), ("%spv", "%t.spv")]

    # lit tries substitutions in list order, and a short pattern would match
    # inside a longer one (%spv inside %spvasm). Longest first avoids that.
    # lit's own %s and %t always come after these.
    substitutions.sort(key=lambda pair: len(pair[0]), reverse=True)
    config.substitutions += substitutions

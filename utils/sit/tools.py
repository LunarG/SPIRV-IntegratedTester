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

"""Tool paths, and the lit --param options that override them.

CMake writes the paths it found into lit.site.cfg.py. These options replace
them for one run without a reconfigure, for example to test a local
SPIRV-Tools build:

    sit-lit.py --param spirv_tools_dir=$HOME/SPIRV-Tools/build/tools -sv tests
    sit-lit.py --param slangc=/opt/slang/bin/slangc -sv tests

Kept free of lit imports so that watch.py can use it before lit is loaded.
"""
from __future__ import annotations

import os
import sys

# Compilers, as substitution names. Each test needs one of these.
COMPILERS = ("slangc", "glslang", "dxc")

# The SPIRV-Tools executables that --param spirv_tools_dir points at, as
# (substitution name, executable name) pairs.
SPIRV_TOOLS = (
    ("spirv_dis", "spirv-dis"),
    ("spirv_opt", "spirv-opt"),
    ("spirv_val", "spirv-val"),
)

SPIRV_TOOLS_DIR_PARAM = "spirv_tools_dir"


def _abs(path: str) -> str:
    """lit runs each test in its Output/ directory, so a relative path from the
    command line has to be made absolute against the directory lit ran in."""
    return os.path.abspath(os.path.expanduser(path))


def _exe(name: str) -> str:
    return name + ".exe" if sys.platform == "win32" else name


def resolve(site_tools: dict[str, str], params: dict[str, str]) -> tuple[dict[str, str], list[str]]:
    """Apply --param overrides to the tool paths from lit.site.cfg.py.

    `--param spirv_tools_dir=DIR` sets all three SPIRV-Tools executables.
    `--param <name>=PATH` sets one tool, where <name> is the substitution
    without the %, and wins over spirv_tools_dir.

    Returns the resolved paths and the names of the tools that were overridden.
    """
    tools = dict(site_tools)
    overridden = []

    tools_dir = params.get(SPIRV_TOOLS_DIR_PARAM)
    if tools_dir:
        for name, exe in SPIRV_TOOLS:
            tools[name] = os.path.join(_abs(tools_dir), _exe(exe))
            overridden.append(name)

    for name in site_tools:
        path = params.get(name)
        if path:
            tools[name] = _abs(path)
            if name not in overridden:
                overridden.append(name)

    return tools, overridden

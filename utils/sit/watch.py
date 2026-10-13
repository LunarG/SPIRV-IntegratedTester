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

"""sit-lit.py --watch: run lit, then run it again whenever something changes.

lit has no watch mode of its own, so this wraps it. Each run is a fresh
"sit-lit.py <args>" process, so a change to the harness itself takes effect.

    a test file changes  -> rerun only the changed tests (with --filter)
    a tool changes       -> rerun everything; a rebuild of FileCheck or a
                            SPIRV-Tools executable counts, as does a tool
                            given with --param
    harness code or a    -> rerun everything
    lit config changes

It polls modification times, which needs nothing beyond the Python standard
library and works the same on every platform.
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
import time
import types

from . import tools as sit_tools

POLL_SECONDS = 0.5
# A build writes several files, and an editor can save in several steps.
# Changes are collected until nothing has changed for this long.
SETTLE_SECONDS = 1.0

# Files under tests/ that configure lit rather than being tests.
CONFIG_NAMES = ("lit.cfg.py", "lit.local.cfg", "lit.site.cfg.py.in")


def _site_tools(site_cfg: str) -> dict[str, str]:
    """Read the tool paths from a generated lit.site.cfg.py.

    The file is Python that expects lit's `config` and `lit_config`. Stand-ins
    collect what it sets, and its final load_config() call does nothing.
    """
    config = types.SimpleNamespace()
    lit_config = types.SimpleNamespace(load_config=lambda *args: None)
    with open(site_cfg, encoding="utf-8") as f:
        code = compile(f.read(), site_cfg, "exec")
    exec(code, {"config": config, "lit_config": lit_config})  # pylint: disable=exec-used
    return config.sit_tools


def _params(lit_args: list[str]) -> dict[str, str]:
    """Return the --param / -D values in a lit command line."""
    params = {}
    args = iter(lit_args)
    for arg in args:
        if arg in ("--param", "-D"):
            value = next(args, "")
        elif arg.startswith("--param="):
            value = arg[len("--param="):]
        elif arg.startswith("-D") and len(arg) > 2:
            value = arg[2:]
        else:
            continue
        name, _, path = value.partition("=")
        params[name] = path
    return params


def _snapshot(dirs: list[str], files: list[str]) -> dict[str, tuple[int, int]]:
    """Return {path: (mtime, size)} for every file under `dirs` and each of `files`."""
    paths = list(files)
    for top in dirs:
        for root, subdirs, names in os.walk(top):
            subdirs[:] = [d for d in subdirs if d != "__pycache__"]
            paths.extend(os.path.join(root, name) for name in names)
    result = {}
    for path in paths:
        try:
            stat = os.stat(path)
        except OSError:
            continue  # Deleted, or not built yet.
        result[path] = (stat.st_mtime_ns, stat.st_size)
    return result


def _wait_for_change(before, dirs, files):
    """Block until the watched files change and settle. Return the new snapshot."""
    while True:
        time.sleep(POLL_SECONDS)
        after = _snapshot(dirs, files)
        if after != before:
            break
    while True:
        time.sleep(SETTLE_SECONDS)
        settled = _snapshot(dirs, files)
        if settled == after:
            return settled
        after = settled


def _run(wrapper: str, args: list[str], reason: str) -> None:
    stamp = time.strftime("%H:%M:%S")
    print(f"\n=== {stamp} sit-lit --watch: {reason} ===", flush=True)
    subprocess.call([sys.executable, wrapper, *args])
    print("=== waiting for changes (Ctrl+C to stop) ===", flush=True)


def main(wrapper: str, src_root: str, obj_root: str, lit_args: list[str]) -> int:
    """Run lit with `lit_args`, then again on every change, until Ctrl+C."""
    tests_dir = os.path.join(src_root, "tests")
    site_cfg = os.path.join(obj_root, "tests", "lit.site.cfg.py")
    tool_paths, _ = sit_tools.resolve(_site_tools(site_cfg), _params(lit_args))

    dirs = [tests_dir, os.path.join(src_root, "utils")]
    files = [site_cfg] + [path for path in tool_paths.values() if path]

    try:
        snapshot = _snapshot(dirs, files)
        _run(wrapper, lit_args, "first run")
        while True:
            new = _wait_for_change(snapshot, dirs, files)
            changed = sorted(p for p in set(snapshot) | set(new) if snapshot.get(p) != new.get(p))
            snapshot = new

            changed_tests = [
                p for p in changed
                if p in new
                and os.path.commonpath([p, tests_dir]) == tests_dir
                and os.path.basename(p) not in CONFIG_NAMES
            ]
            if len(changed_tests) == len(changed):
                # lit names a test "<suite> :: <path in suite>" and --filter
                # searches that name. --allow-empty-runs covers a changed test
                # that is outside the paths given on the command line.
                names = [os.path.relpath(p, tests_dir).replace(os.sep, "/") for p in changed_tests]
                pattern = " :: (?:" + "|".join(re.escape(n) for n in names) + ")$"
                _run(wrapper, [*lit_args, f"--filter={pattern}", "--allow-empty-runs"],
                     "changed: " + ", ".join(names))
            else:
                others = [os.path.relpath(p) for p in changed if p not in changed_tests]
                _run(wrapper, lit_args, "changed: " + ", ".join(others[:3])
                     + (f" and {len(others) - 3} more" if len(others) > 3 else ""))
    except KeyboardInterrupt:
        print()
        return 0

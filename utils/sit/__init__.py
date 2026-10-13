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

"""lit support for the SPIR-V Integrated Tester.

lit has no plugin registry. Its config files are Python that lit runs with
`config` and `lit_config` in scope, so tests/lit.cfg.py puts this directory on
sys.path and calls into this package, the same way libcxx keeps its lit code in
libcxx/utils/libcxx/test/.

    config.py    suite setup: suffixes, tool substitutions, features, --param
    tools.py     tool paths, with --param overrides
    format.py    SpirvTest, the custom lit test format
    pipeline.py  expands a terse RUN: line into the full pipeline
    report.py    the failure report (comment block around the failed CHECK)
    watch.py     sit-lit.py --watch
"""

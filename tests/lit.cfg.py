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

"""lit config for the suite.

lit runs this file with `config` and `lit_config` in scope. Run the suite
through <build>/sit-lit.py, which loads the generated
<build>/tests/lit.site.cfg.py first; that sets the tool paths, then loads this.
"""
# pylint: disable=undefined-variable

import os
import sys

if not hasattr(config, "sit_tools"):
    lit_config.fatal(
        "tests/lit.cfg.py was loaded without a site config, so no tool paths are known. "
        "Run the suite with <build>/sit-lit.py, or point lit at <build>/tests.")

sys.path.insert(0, os.path.join(config.sit_src_root, "utils"))
import sit.config  # pylint: disable=wrong-import-position

sit.config.configure(config, lit_config)

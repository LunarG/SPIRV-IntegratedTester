#!/bin/bash

set -e

python3 spirv_tester.py                                 # run all tests (auto-discovers build/sit.cfg.json)
python3 spirv_tester.py tests/slang/example.slang       # single test
python3 spirv_tester.py -v                              # verbose (show PASSes)
python3 spirv_tester.py --tmp-dir /tmp/sit-debug        # debugging directory
python3 spirv_tester.py --config build/sit.cfg.json     # explicit config

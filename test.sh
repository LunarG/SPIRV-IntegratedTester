#!/bin/bash

set -e

#python3 spirv_tester.py build/sit.cfg.py                           # run all tests
#python3 spirv_tester.py build/sit.cfg.py tests/slang/example.slang # single test
#python3 spirv_tester.py build/sit.cfg.py -v                        # verbose (show PASSes)

python3 spirv_tester.py build/sit.cfg.py --tmp-dir /tmp/sit-debug   # debugging directory

#!/usr/bin/env python3
"""Prints a one-line test summary plus every failure message, from
`xcresulttool get test-results summary --compact` JSON on stdin."""
import json
import sys

summary = json.load(sys.stdin)
print(f"Tests: {summary.get('passedTests')} passed, "
      f"{summary.get('failedTests')} failed, {summary.get('skippedTests')} skipped")
for failure in summary.get("testFailures", []):
    print(f"FAIL {failure.get('testIdentifierString')}: {failure.get('failureText')}")

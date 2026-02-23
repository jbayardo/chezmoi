#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Update television channels."""

import subprocess
import sys

subprocess.run(
    ["tv", "update-channels", "--force"],
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
)

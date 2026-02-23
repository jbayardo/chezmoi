#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Interactive git diff viewer using fzf and delta."""

import shutil
import subprocess
import sys


def main():
    extra_args = sys.argv[1:] if len(sys.argv) > 1 else []

    fzf = shutil.which("fzf")
    if not fzf:
        print("fzf not found", file=sys.stderr)
        sys.exit(1)

    diff_cmd = ["git", "diff", "--name-only"] + extra_args
    result = subprocess.run(diff_cmd, capture_output=True, text=True)

    if not result.stdout.strip():
        print("No changes found")
        sys.exit(0)

    delta = shutil.which("delta")
    if extra_args:
        preview = f"git diff {' '.join(extra_args)} -- {{}}"
    else:
        preview = "git diff {}"

    if delta:
        preview += " | delta --width=$FZF_PREVIEW_COLUMNS"

    fzf_args = [
        fzf,
        "--preview", preview,
        "--preview-window=up,70%",
        "--bind", "ctrl-j:preview-down,ctrl-k:preview-up,ctrl-u:preview-half-page-up,ctrl-i:preview-half-page-down",
        "--height=100%",
    ]

    subprocess.run(fzf_args, input=result.stdout, text=True)


if __name__ == "__main__":
    main()

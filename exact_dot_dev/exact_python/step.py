#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""AI-powered git commit: stage all changes, generate commit message, commit and push."""

import shutil
import subprocess
import sys


def run(*args, **kwargs):
    """Run a command and return its result."""
    return subprocess.run(args, capture_output=True, text=True, **kwargs)


def main():
    # Capture untracked files before staging
    untracked = run("git", "ls-files", "--others", "--exclude-standard")
    untracked_files = [f for f in untracked.stdout.strip().split("\n") if f]

    # Stage all changes
    run("git", "add", "-A", ":/")

    # Check if there are staged changes
    if run("git", "diff", "--cached", "--quiet", "HEAD").returncode == 0:
        print("No changes to commit")
        sys.exit(1)

    # Get branch name and diff
    branch = run("git", "rev-parse", "--abbrev-ref", "HEAD").stdout.strip() or "unknown"
    diff = run("git", "diff", "--cached", "HEAD").stdout

    # Get content of newly tracked files
    untracked_content = ""
    for f in untracked_files:
        result = run("git", "show", f":0:{f}")
        if result.returncode == 0:
            untracked_content += f"\nNew file: {f}\n{result.stdout}"

    prompt = (
        f"Read the following changes. The current branch is '{branch}'. "
        "Generate a concise commit message following conventional commit format. "
        "Output ONLY the commit message, nothing else.\n\n"
        f"{diff}"
    )
    if untracked_content:
        prompt += f"\n{untracked_content}"

    # Generate commit message with copilot
    copilot = shutil.which("copilot")
    commit_msg = None
    if copilot:
        result = run(
            copilot, "--silent", "--allow-all-tools", "--model", "gpt-4.1",
            input=prompt,
        )
        if result.returncode == 0 and result.stdout.strip():
            commit_msg = result.stdout.strip()

    if not commit_msg:
        print("Failed to generate commit message", file=sys.stderr)
        sys.exit(1)

    # Commit and push
    result = run("git", "commit", "-m", commit_msg)
    if result.returncode != 0:
        print(f"git commit failed: {result.stderr}", file=sys.stderr)
        sys.exit(1)
    print(result.stdout, end="")

    result = run("git", "push")
    print(result.stdout, end="")
    print(result.stderr, end="")


if __name__ == "__main__":
    main()

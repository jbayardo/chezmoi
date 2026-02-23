#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Create a new git branch with an AI-generated or user-provided name."""

import re
import shutil
import subprocess
import sys
from datetime import datetime


def run(*args, **kwargs):
    """Run a command and return its result."""
    return subprocess.run(args, capture_output=True, text=True, **kwargs)


def get_username():
    """Get a sanitized username for branch naming."""
    result = run("git", "config", "user.name")
    name = result.stdout.strip()
    if name:
        return re.sub(r"[^a-z0-9-]", "-", name.lower()).strip("-")
    import os
    return os.environ.get("USER", os.environ.get("USERNAME", "user")).lower()


def sanitize_branch(name):
    """Sanitize a string into a valid branch name component."""
    return re.sub(r"[^a-z0-9-]", "", name.lower().split("\n")[0])[:50]


def generate_branch_name(prompt_text=None):
    """Generate a branch name using copilot or fallback to timestamp."""
    copilot = shutil.which("copilot")

    diff = run("git", "diff", "HEAD").stdout.strip()
    untracked = run("git", "ls-files", "--others", "--exclude-standard").stdout.strip()
    has_changes = bool(diff or untracked)

    if copilot and (prompt_text or has_changes):
        if prompt_text and has_changes:
            prompt = (
                f"Read the following changes and the prompt: '{prompt_text}'. "
                "Generate a short, descriptive git branch name (lowercase, hyphens, "
                "no special chars, max 50 chars). Output ONLY the branch name.\n\n"
                f"{diff}"
            )
        elif prompt_text:
            prompt = (
                f"Generate a short, descriptive git branch name for: '{prompt_text}'. "
                "Lowercase, hyphens, no special chars, max 50 chars. Output ONLY the branch name."
            )
        else:
            prompt = (
                "Generate a short, descriptive git branch name from these changes. "
                "Lowercase, hyphens, no special chars, max 50 chars. Output ONLY the branch name.\n\n"
                f"{diff}"
            )

        result = run(copilot, "--silent", "--allow-all-tools", "--model", "gpt-4.1", input=prompt)
        if result.returncode == 0 and result.stdout.strip():
            return sanitize_branch(result.stdout.strip())

    return datetime.now().strftime("%Y%m%d%H%M%S")


def main():
    prompt_text = " ".join(sys.argv[1:]) if len(sys.argv) > 1 else None

    # If the argument contains a slash, use it as-is (full branch path)
    if prompt_text and "/" in prompt_text:
        full_branch = prompt_text
    else:
        username = get_username()
        branch_name = generate_branch_name(prompt_text)
        full_branch = f"dev/{username}/{branch_name}"

    print(f"Creating and checking out branch: {full_branch}")
    result = run("git", "checkout", "-b", full_branch)
    if result.returncode != 0:
        print(f"Failed: {result.stderr}", file=sys.stderr)
        sys.exit(1)
    print(result.stderr, end="")


if __name__ == "__main__":
    main()

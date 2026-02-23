#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""Find and select a git repository using fzf. Prints selected path to stdout."""

import os
import shutil
import subprocess
import sys
from pathlib import Path


def find_src_dirs():
    """Find source directories to search for repos."""
    home = Path.home()
    if sys.platform == "win32":
        candidates = [
            Path("C:/src"), Path("Q:/src"), Path("D:/src"),
            Path("Q:/"), Path("D:/"),
        ]
    else:
        candidates = [
            home / "src",
            Path("/mnt/c/src"), Path("/mnt/q/src"), Path("/mnt/d/src"),
            Path("/mnt/q"), Path("/mnt/d"),
        ]
    return [d for d in candidates if d.is_dir()]


def find_repos(src_dirs):
    """Find git repositories up to depth 3."""
    repos = set()
    for src_dir in src_dirs:
        for root, dirs, files in os.walk(str(src_dir)):
            depth = root.replace(str(src_dir), "").count(os.sep)
            if depth >= 3:
                dirs.clear()
                continue
            if ".git" in dirs or ".git" in files:
                repos.add(root)
                dirs.clear()
    return sorted(repos)


def get_branch(repo_path):
    """Get the current branch of a repo."""
    try:
        result = subprocess.run(
            ["git", "-C", repo_path, "branch", "--show-current"],
            capture_output=True, text=True, timeout=5,
        )
        return result.stdout.strip() or "detached"
    except Exception:
        return "unknown"


def main():
    query = " ".join(sys.argv[1:]) if len(sys.argv) > 1 else ""

    src_dirs = find_src_dirs()
    if not src_dirs:
        print("No source directories found", file=sys.stderr)
        sys.exit(1)

    repos = find_repos(src_dirs)
    if not repos:
        print("No git repositories found", file=sys.stderr)
        sys.exit(1)

    fzf = shutil.which("fzf")
    if not fzf:
        print("fzf not found", file=sys.stderr)
        sys.exit(1)

    # If only one match for the query, go directly
    if query:
        filtered = [r for r in repos if query.lower() in r.lower()]
        if len(filtered) == 1:
            print(filtered[0])
            return

    # Build display with branch info
    display_lines = []
    for repo in repos:
        branch = get_branch(repo)
        display_lines.append(f"{repo}\t({branch})")

    fzf_args = [
        fzf,
        "--prompt=repo> ",
        "--delimiter=\t",
        "--with-nth=1..",
        "--preview", (
            "echo '── status ──' && git -C {1} status -sb && echo '' && "
            "echo '── log ──' && git -C {1} log --oneline --graph --decorate -10 --color 2>/dev/null"
        ),
        "--preview-window=right:50%",
    ]
    if query:
        fzf_args.extend(["--query", query])

    result = subprocess.run(
        fzf_args,
        input="\n".join(display_lines),
        text=True,
        stdout=subprocess.PIPE,
    )
    if result.returncode != 0 or not result.stdout.strip():
        sys.exit(1)

    selected = result.stdout.strip().split("\t")[0]
    print(selected)


if __name__ == "__main__":
    main()

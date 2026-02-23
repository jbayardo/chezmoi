#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "tomli>=2.0.0",
# ]
# ///
"""Cross-platform tool installer. Reads tools.toml and installs packages using the appropriate package manager."""

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib


def run(*args, check=False, **kwargs):
    """Run a command, printing it first."""
    print(f"  → {' '.join(args)}")
    return subprocess.run(args, check=check, **kwargs)


def install_cargo_packages(packages: list[str], github_token: str | None = None):
    """Install cargo packages using cargo-binstall if available, otherwise cargo install."""
    if not shutil.which("cargo"):
        print("⚠ cargo not found, skipping Rust packages")
        return

    binstall = shutil.which("cargo-binstall") is not None
    failures = []

    for pkg in packages:
        print(f"📦 Installing {pkg}...")
        if binstall:
            cmd = ["cargo", "binstall", "--force", "--no-confirm", "--locked", pkg]
            if github_token:
                cmd.insert(2, f"--github-token={github_token}")
        else:
            cmd = ["cargo", "install", "--locked", pkg]

        result = run(*cmd)
        if result.returncode != 0:
            failures.append(pkg)

    if failures:
        print(f"\n⚠ Failed to install: {', '.join(failures)}", file=sys.stderr)


def install_go_packages(packages: list[str]):
    """Install Go packages."""
    if not shutil.which("go"):
        print("⚠ go not found, skipping Go packages")
        return

    failures = []
    for pkg in packages:
        print(f"📦 Installing {pkg}...")
        result = run("go", "install", f"{pkg}@latest")
        if result.returncode != 0:
            failures.append(pkg)

    if failures:
        print(f"\n⚠ Failed to install: {', '.join(failures)}", file=sys.stderr)


def install_uv_tools(packages: list[str]):
    """Install Python tools using uv."""
    if not shutil.which("uv"):
        print("⚠ uv not found, skipping Python tools")
        return

    failures = []
    for pkg in packages:
        print(f"📦 Installing {pkg}...")
        result = run("uv", "tool", "install", pkg)
        if result.returncode != 0:
            failures.append(pkg)

    if failures:
        print(f"\n⚠ Failed to install: {', '.join(failures)}", file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(description="Install tools from tools.toml")
    parser.add_argument("--cargo", action="store_true", help="Install Rust/cargo packages")
    parser.add_argument("--go", action="store_true", help="Install Go packages")
    parser.add_argument("--python", action="store_true", help="Install Python tools")
    parser.add_argument("--all", action="store_true", help="Install everything")
    parser.add_argument(
        "--manifest", type=Path,
        default=Path.home() / ".dev" / "tools.toml",
        help="Path to tools.toml manifest",
    )
    args = parser.parse_args()

    if not args.manifest.exists():
        print(f"Manifest not found: {args.manifest}", file=sys.stderr)
        sys.exit(1)

    with open(args.manifest, "rb") as f:
        manifest = tomllib.load(f)

    if args.all:
        args.cargo = args.go = args.python = True

    if not any([args.cargo, args.go, args.python]):
        parser.print_help()
        sys.exit(1)

    # Get GitHub token for cargo-binstall rate limiting
    github_token = None
    if shutil.which("gh"):
        result = subprocess.run(["gh", "auth", "token"], capture_output=True, text=True)
        if result.returncode == 0:
            github_token = result.stdout.strip()

    if args.cargo:
        packages = manifest.get("cargo", {}).get("packages", [])
        if packages:
            print(f"\n🦀 Installing {len(packages)} cargo packages...\n")
            install_cargo_packages(packages, github_token)

    if args.go:
        packages = manifest.get("go", {}).get("packages", [])
        if packages:
            print(f"\n🐹 Installing {len(packages)} Go packages...\n")
            install_go_packages(packages)

    if args.python:
        packages = manifest.get("python", {}).get("tools", [])
        if packages:
            print(f"\n🐍 Installing {len(packages)} Python tools...\n")
            install_uv_tools(packages)

    print("\n✅ Done!")


if __name__ == "__main__":
    main()

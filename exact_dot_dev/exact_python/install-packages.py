#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "pyyaml>=6.0",
# ]
# ///
"""Cross-platform declarative package installer.

Reads a YAML manifest defining sources, profiles, and packages.
Determines which packages need installing based on the active profile,
checks what's already present, and installs only what's missing.
"""

import argparse
import os
import platform
import re
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import yaml


def get_os() -> str:
    """Return normalized OS name matching chezmoi conventions."""
    s = platform.system().lower()
    if s == "darwin":
        return "darwin"
    elif s == "windows":
        return "windows"
    return "linux"


def run_silent(cmd: str, shell: bool = True) -> int:
    """Run a command silently, return exit code."""
    try:
        result = subprocess.run(
            cmd, shell=shell, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        return result.returncode
    except Exception:
        return 1


def run_capture(cmd: str, shell: bool = True) -> tuple[int, str]:
    """Run a command and capture stdout."""
    try:
        result = subprocess.run(
            cmd, shell=shell, capture_output=True, text=True
        )
        return result.returncode, result.stdout
    except Exception:
        return 1, ""


def check_source_available(source_cfg: dict) -> bool:
    """Check if a package source is available on this system."""
    cmd = source_cfg.get("available", "")
    if not cmd:
        return False
    return run_silent(cmd) == 0


def check_package_installed(pkg_id: str, source_name: str, source_cfg: dict, pkg_cfg: dict) -> bool:
    """Check if a package is already installed."""
    # Method 1: check_cmd + check_grep (list and grep)
    if "check_cmd" in source_cfg and "check_grep" in source_cfg:
        pattern = source_cfg["check_grep"].replace("{pkg}", re.escape(pkg_id))
        rc, stdout = run_capture(source_cfg["check_cmd"])
        if rc != 0:
            return False
        return bool(re.search(pattern, stdout, re.MULTILINE))

    # Method 2: check_binary (for go packages — check if the binary exists)
    if source_cfg.get("check_binary"):
        binary = pkg_cfg.get("binary", pkg_id.split("/")[-1])
        return shutil.which(binary) is not None

    # Method 3: check command template (exit code based)
    if "check" in source_cfg:
        cmd = source_cfg["check"].replace("{pkg}", pkg_id)
        return run_silent(cmd) == 0

    # Fallback: check if binary is in PATH
    binary = pkg_cfg.get("binary", pkg_id)
    return shutil.which(binary) is not None


def install_package(pkg_id: str, source_name: str, source_cfg: dict) -> bool:
    """Install a package. Returns True on success."""
    cmd = source_cfg["install"].replace("{pkg}", pkg_id)
    print(f"  → {cmd}")
    result = subprocess.run(cmd, shell=True)
    return result.returncode == 0


def get_github_token() -> str | None:
    """Get GitHub token for cargo-binstall rate limiting."""
    if not shutil.which("gh"):
        return None
    rc, stdout = run_capture("gh auth token")
    if rc == 0 and stdout.strip():
        return stdout.strip()
    return None


def main():
    parser = argparse.ArgumentParser(description="Declarative cross-platform package installer")
    parser.add_argument(
        "--profile", type=str, default=os.environ.get("DOTFILES_PROFILE", "personal"),
        help="Profile to use (default: $DOTFILES_PROFILE or 'personal')",
    )
    parser.add_argument(
        "--manifest", type=Path,
        default=Path.home() / ".dev" / "packages.yaml",
        help="Path to packages.yaml manifest",
    )
    parser.add_argument("--dry-run", action="store_true", help="Show what would be installed without installing")
    parser.add_argument("--source", type=str, help="Only install from a specific source")
    parser.add_argument("--verbose", action="store_true", help="Show detailed output")
    args = parser.parse_args()

    if not args.manifest.exists():
        print(f"✗ Manifest not found: {args.manifest}", file=sys.stderr)
        sys.exit(1)

    with open(args.manifest) as f:
        manifest = yaml.safe_load(f)

    current_os = get_os()
    profile_name = args.profile
    profile = manifest.get("profiles", {}).get(profile_name)
    if not profile:
        print(f"✗ Unknown profile: {profile_name}", file=sys.stderr)
        print(f"  Available: {', '.join(manifest.get('profiles', {}).keys())}")
        sys.exit(1)

    source_prefs = profile.get("source_preference", {}).get(current_os, [])
    if not source_prefs:
        print(f"✗ No source preferences for OS '{current_os}' in profile '{profile_name}'", file=sys.stderr)
        sys.exit(1)

    sources = manifest.get("sources", {})
    packages = manifest.get("packages", {})

    # Filter to requested source if specified
    if args.source:
        if args.source not in sources:
            print(f"✗ Unknown source: {args.source}", file=sys.stderr)
            sys.exit(1)
        source_prefs = [s for s in source_prefs if s == args.source]

    # Check which sources are available
    print(f"🖥  OS: {current_os} | Profile: {profile_name}")
    print(f"📋 Source preference: {' > '.join(source_prefs)}\n")

    available_sources: dict[str, dict] = {}
    for src_name in source_prefs:
        src_cfg = sources.get(src_name, {})
        if check_source_available(src_cfg):
            available_sources[src_name] = src_cfg
            if args.verbose:
                print(f"  ✓ {src_name} available")
        else:
            if args.verbose:
                print(f"  ✗ {src_name} not available")

    if not available_sources:
        print("✗ No package sources available!", file=sys.stderr)
        sys.exit(1)

    print(f"🔍 Available sources: {', '.join(available_sources.keys())}\n")

    # Set GITHUB_TOKEN for cargo-binstall if available
    gh_token = get_github_token()
    if gh_token and "cargo" in available_sources:
        cargo_cfg = available_sources["cargo"]
        if "--github-token" not in cargo_cfg.get("install", ""):
            cargo_cfg["install"] = cargo_cfg["install"].replace(
                "cargo binstall",
                f"cargo binstall --github-token={gh_token}",
            )

    # Pre-cache list outputs for sources that use check_cmd (cargo, uv, dotnet)
    # This avoids running the same list command per-package
    source_list_cache: dict[str, str] = {}
    def get_source_list(src_name: str, src_cfg: dict) -> str:
        if src_name not in source_list_cache:
            if "check_cmd" in src_cfg:
                _, stdout = run_capture(src_cfg["check_cmd"])
                source_list_cache[src_name] = stdout
            else:
                source_list_cache[src_name] = ""
        return source_list_cache[src_name]

    # Pre-populate caches in parallel
    list_sources = [s for s in available_sources if "check_cmd" in available_sources[s]]
    with ThreadPoolExecutor(max_workers=len(list_sources) or 1) as pool:
        futures = {pool.submit(get_source_list, s, available_sources[s]): s for s in list_sources}
        for f in as_completed(futures):
            f.result()

    def check_package_installed_cached(pkg_id: str, src_name: str, src_cfg: dict, pkg_cfg: dict) -> bool:
        """Check if a package is installed, using cached list output."""
        if "check_cmd" in src_cfg and "check_grep" in src_cfg:
            pattern = src_cfg["check_grep"].replace("{pkg}", re.escape(pkg_id))
            stdout = source_list_cache.get(src_name, "")
            return bool(re.search(pattern, stdout, re.MULTILINE))
        return check_package_installed(pkg_id, src_name, src_cfg, pkg_cfg)

    # Resolve packages for this profile
    to_install: list[tuple[str, str, str, dict]] = []  # (pkg_name, source_name, pkg_id, pkg_cfg)
    already_installed: list[tuple[str, str]] = []  # (pkg_name, how_detected)
    skipped: list[tuple[str, str]] = []  # (pkg_name, reason)

    # Build list of packages to check
    to_check: list[tuple[str, dict]] = []
    for pkg_name, pkg_cfg in packages.items():
        pkg_profiles = pkg_cfg.get("profiles", [])
        if profile_name not in pkg_profiles:
            continue
        to_check.append((pkg_name, pkg_cfg))

    def resolve_package(pkg_name: str, pkg_cfg: dict) -> tuple[str, str, str | None, str | None, dict]:
        """Resolve a single package. Returns (pkg_name, status, src_name, pkg_id, pkg_cfg).
        status is 'installed', 'to_install', or 'skipped'."""
        pkg_sources = pkg_cfg.get("sources", {})

        # First: check if the binary is already in PATH
        binary = pkg_cfg.get("binary", pkg_name)
        if shutil.which(binary):
            return (pkg_name, "installed", f"binary '{binary}' in PATH", None, pkg_cfg)

        # Second: check each source's own detection method
        for src_name in source_prefs:
            if src_name not in available_sources:
                continue
            if src_name not in pkg_sources:
                continue
            pkg_id = pkg_sources[src_name]
            src_cfg = available_sources[src_name]
            if check_package_installed_cached(pkg_id, src_name, src_cfg, pkg_cfg):
                return (pkg_name, "installed", f"detected via {src_name}", None, pkg_cfg)

        # Third: find the preferred source to install from
        for src_name in source_prefs:
            if src_name not in available_sources:
                continue
            if src_name not in pkg_sources:
                continue
            pkg_id = pkg_sources[src_name]
            return (pkg_name, "to_install", src_name, pkg_id, pkg_cfg)

        # No source available
        available_for = [s for s in pkg_sources if s in available_sources]
        if not available_for:
            return (pkg_name, "skipped", "no available source", None, pkg_cfg)
        return (pkg_name, "skipped", "not in source preference", None, pkg_cfg)

    # Run checks in parallel
    with ThreadPoolExecutor(max_workers=os.cpu_count() or 4) as pool:
        futures = {pool.submit(resolve_package, name, cfg): name for name, cfg in to_check}
        for future in as_completed(futures):
            pkg_name, status, info, pkg_id, pkg_cfg = future.result()
            if status == "installed":
                already_installed.append((pkg_name, info))
            elif status == "to_install":
                to_install.append((pkg_name, info, pkg_id, pkg_cfg))
            else:
                skipped.append((pkg_name, info))

    # Summary
    print(f"✓ Already installed: {len(already_installed)}")
    if args.verbose:
        for name, how in already_installed:
            print(f"    {name}: {how}")
    print(f"📦 To install: {len(to_install)}")
    if to_install:
        by_source_display: dict[str, list[tuple[str, str]]] = {}
        for pkg_name, src_name, pkg_id, _ in to_install:
            by_source_display.setdefault(src_name, []).append((pkg_name, pkg_id))
        for src_name, pkgs in by_source_display.items():
            print(f"  [{src_name}]")
            for pkg_name, pkg_id in pkgs:
                print(f"    {pkg_name} ({pkg_id})")
    if skipped:
        print(f"⚠ Skipped: {len(skipped)}")
        for name, reason in skipped:
            print(f"    {name}: {reason}")
    print()

    if not to_install:
        print("✅ Everything is installed!")
        return

    if args.dry_run:
        return

    # Group by source for installation
    by_source: dict[str, list[tuple[str, str, dict]]] = {}
    for pkg_name, src_name, pkg_id, pkg_cfg in to_install:
        by_source.setdefault(src_name, []).append((pkg_name, pkg_id, pkg_cfg))

    # Install
    failures: list[tuple[str, str]] = []
    for src_name, pkgs in by_source.items():
        src_cfg = available_sources[src_name]
        print(f"📦 Installing from {src_name} ({len(pkgs)} packages):\n")
        for pkg_name, pkg_id, pkg_cfg in pkgs:
            print(f"  [{pkg_name}] via {src_name}:")
            if not install_package(pkg_id, src_name, src_cfg):
                failures.append((pkg_name, src_name))
                print(f"    ✗ Failed\n")
            else:
                print(f"    ✓ Done\n")

    if failures:
        print(f"\n⚠ {len(failures)} package(s) failed to install:")
        for pkg_name, src_name in failures:
            print(f"    {pkg_name} ({src_name})")
        sys.exit(1)
    else:
        print("\n✅ All packages installed!")


if __name__ == "__main__":
    main()

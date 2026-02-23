#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "paramiko>=3.4.0",
# ]
# ///
"""Mount encrypted Jellyfin storage devices on remote host."""

import getpass
import subprocess
import sys
from pathlib import Path
from typing import NamedTuple

import paramiko


class DeviceConfig(NamedTuple):
    """Configuration for an encrypted device."""

    device: str
    mapper_name: str
    mount_point: str
    keepass_entry: str


# Configuration
KEEPASS_DB = Path.home() / "Sync" / "passwords.kdbx"
REMOTE_HOST = "garfio"

DEVICES = [
    DeviceConfig(
        device="/dev/sdb1",
        mapper_name="luks-f00ff2b1-fb4a-405e-ac06-7d063724e702",
        mount_point="/media/usb24tb",
        keepass_entry="Garfio LUKS 24TB",
    ),
    DeviceConfig(
        device="/dev/sda1",
        mapper_name="hdd1",
        mount_point="/media/hdd1",
        keepass_entry="Garfio LUKS 2TB HDD",
    ),
]


def get_password_from_keepass(
    db_path: Path, entry_name: str, master_password: str
) -> str:
    """Retrieve a password from KeePassXC database."""
    try:
        result = subprocess.run(
            ["keepassxc-cli", "show", "-s", str(db_path), entry_name, "-a", "Password"],
            input=master_password.encode(),
            capture_output=True,
            check=True,
        )
        return result.stdout.decode().strip()
    except subprocess.CalledProcessError as e:
        print(
            f"[!] Failed to retrieve password for '{entry_name}': {e.stderr.decode()}",
            file=sys.stderr,
        )
        raise


def create_remote_script(devices: list[DeviceConfig], passwords: dict[str, str]) -> str:
    """Generate the bash script to run on the remote host."""
    script_lines = ["#!/usr/bin/env bash", "set -e", ""]

    # Add the mount function
    script_lines.extend(
        [
            "mount_encrypted_device() {",
            '    local DEVICE="$1"',
            '    local MAPPER_NAME="$2"',
            '    local MOUNT_POINT="$3"',
            '    local PASSWORD="$4"',
            '    local MAPPER_PATH="/dev/mapper/$MAPPER_NAME"',
            "",
            '    echo "======================================"',
            '    echo "[*] Processing encrypted device:"',
            '    echo "    Device:      $DEVICE"',
            '    echo "    Mapper name: $MAPPER_NAME"',
            '    echo "    Mount point: $MOUNT_POINT"',
            '    echo "    Mapper path: $MAPPER_PATH"',
            '    echo ""',
            "",
            "    # Check if already mapped",
            '    if [ -e "$MAPPER_PATH" ]; then',
            '        echo "[+] Device $DEVICE already unlocked as $MAPPER_PATH"',
            "    else",
            '        echo "[*] Unlocking encrypted device $DEVICE..."',
            '        echo -n "$PASSWORD" | sudo -S cryptsetup open --key-file=- "$DEVICE" "$MAPPER_NAME" || { echo "[!] Failed to unlock device $DEVICE"; exit 1; }',
            '        echo "[+] Successfully unlocked $DEVICE as $MAPPER_PATH"',
            "    fi",
            "",
            "    # Create mount point if it doesn't exist",
            '    if [ ! -d "$MOUNT_POINT" ]; then',
            '        echo "[*] Creating mount point at $MOUNT_POINT"',
            '        sudo mkdir -p "$MOUNT_POINT"',
            '        echo "[+] Mount point created"',
            "    else",
            '        echo "[*] Mount point $MOUNT_POINT already exists"',
            "    fi",
            "",
            "    # Mount if not already mounted",
            '    if mountpoint -q "$MOUNT_POINT"; then',
            '        echo "[+] Device $DEVICE already mounted at $MOUNT_POINT"',
            "    else",
            '        echo "[*] Mounting $MAPPER_PATH to $MOUNT_POINT..."',
            '        sudo mount "$MAPPER_PATH" "$MOUNT_POINT" || { echo "[!] Failed to mount device $DEVICE to $MOUNT_POINT"; exit 1; }',
            '        echo "[+] Successfully mounted $DEVICE to $MOUNT_POINT!"',
            "    fi",
            '    echo ""',
            "}",
            "",
            'echo "[*] Starting device mounting process on remote host..."',
            'echo ""',
            "",
        ]
    )

    # Add mount commands for each device
    for device in devices:
        password = passwords[device.keepass_entry]
        # Escape special characters in password for bash
        escaped_password = password.replace("'", "'\\''")
        script_lines.append(
            f"mount_encrypted_device '{device.device}' '{device.mapper_name}' "
            f"'{device.mount_point}' '{escaped_password}'"
        )

    script_lines.extend(
        [
            "",
            'echo "======================================"',
            'echo "[+] All devices processed successfully!"',
        ]
    )

    return "\n".join(script_lines)


def execute_remote_script(hostname: str, script: str) -> None:
    """Execute a bash script on a remote host via SSH."""
    print(f"[*] Connecting to {hostname}...")

    # Create SSH client
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())

    # Load SSH config
    ssh_config = paramiko.SSHConfig()
    ssh_config_file = Path.home() / ".ssh" / "config"
    if ssh_config_file.exists():
        with open(ssh_config_file, encoding="utf-8") as f:
            ssh_config.parse(f)

    # Get host config
    host_config = ssh_config.lookup(hostname)

    try:
        # Connect using SSH config and agent
        ssh.connect(
            hostname=host_config.get("hostname", hostname),
            port=int(host_config.get("port", 22)),
            username=host_config.get("user"),
            key_filename=host_config.get("identityfile"),
        )
        print(f"[+] Connected to {hostname}")
        print("")

        # Execute the script
        stdin, stdout, stderr = ssh.exec_command("bash -s")
        stdin.write(script)
        stdin.close()

        # Stream output in real-time
        for line in stdout:
            print(line, end="")

        # Print any errors
        error_output = stderr.read().decode()
        if error_output:
            print(error_output, file=sys.stderr)

        # Check exit status
        exit_status = stdout.channel.recv_exit_status()
        if exit_status != 0:
            print(
                f"[!] Remote script exited with status {exit_status}", file=sys.stderr
            )
            sys.exit(exit_status)

    finally:
        ssh.close()


def main() -> None:
    """Main entry point."""
    print("[*] Initializing Jellyfin mount script...")
    print(f"[*] KeePassXC database: {KEEPASS_DB}")
    print("")

    # Get master password
    master_password = getpass.getpass("Enter KeePassXC database password: ")

    # Retrieve passwords from KeePassXC
    print("[*] Retrieving passwords from KeePassXC...")
    passwords = {}

    try:
        for device in DEVICES:
            passwords[device.keepass_entry] = get_password_from_keepass(
                KEEPASS_DB, device.keepass_entry, master_password
            )
        del master_password

        print(f"[+] Successfully retrieved passwords for {len(DEVICES)} devices")
        print("")

    except Exception as e:
        print(f"[!] Failed to retrieve passwords: {e}", file=sys.stderr)
        sys.exit(1)

    # Create and execute remote script
    script = create_remote_script(DEVICES, passwords)

    try:
        execute_remote_script(REMOTE_HOST, script)
        print("")
        print("[+] Mount script completed successfully!")

    except Exception as e:
        print(f"[!] Failed to execute remote script: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()

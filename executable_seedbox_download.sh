#!/bin/bash
rclone copy "seedbox:downloads/manual/" manual --multi-thread-streams 20 --progress --checksum

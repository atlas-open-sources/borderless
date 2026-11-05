#!/bin/bash
# First boot of the Borderless relay box (Amazon Linux 2023, arm64). The deploy bundle does the rest.
set -euo pipefail
# Swap before dnf: a t4g.nano has 512 MB and dnf is OOM-killed installing docker without it (2026-11-04).
if [[ ! -e /swapfile ]]; then
  fallocate -l 1G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi
dnf install -y docker
systemctl enable --now docker

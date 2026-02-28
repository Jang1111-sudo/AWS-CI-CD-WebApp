#!/bin/bash
set -euxo pipefail

dnf -y reinstall nginx
systemctl enable nginx
systemctl start nginx

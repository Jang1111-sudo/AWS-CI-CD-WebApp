#!/bin/bash
set -euxo pipefail
if ! rpm -q nginx; then
	dnf install -y nginx
fi
mkdir -p /usr/share/nginx/html
systemctl enable nginx
systemctl start nginx

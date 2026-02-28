#!/bin/bash
set -euxo pipefail
if rpm -q nginx; then
	systemctl stop nginx || true
	dnf remove -y nginx || true
fi

rm -rf /var/cache/dnf/* || true
rm -f /var/lib/rpm/__db* || true
rpm --rebuilddb || true

dnf -y install nginx

mkdir -p /usr/share/nginx/html
systemctl enable nginx
systemctl start nginx

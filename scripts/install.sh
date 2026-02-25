#!/bin/bash
set -e
dnf install -y nginx
mkdir -p /usr/share/nginx/html
chown -R nginx:nginx /usr/share/nginx/html || true
systemctl enable nginx
systemctl start nginx

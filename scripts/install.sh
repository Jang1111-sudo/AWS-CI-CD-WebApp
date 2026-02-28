#!/bin/bash
set -euxo pipefail

#1) nginx already installed -> reinstall for recover file corruption or missing
#2) nginx not installed -> newly install
if rpm -q nginx > /dev/null 2>&1; then
	dnf -y reinstall nginx
else
	dnf -y install nginx
fi

#ready for web root
mkdir -p /usr/share/nginx/html

systemctl enable nginx
systemctl start nginx

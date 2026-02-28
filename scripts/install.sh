#!/bin/bash
set -euxo pipefail

echo "===install.sh start==="
date
whoami
pwd
ls -al

#install nginx : if already installed it, skip
if ! rpm -q nginx > /dev/null 2>&1; then
	dnf clean all || true
	rm -rf /var/cache/dnf/* || true
	dnf -y install nginx
else
	echo "nginx already installed"
fi

mkdir -p /usr/share/nginx/html
#there could not be nginx user. -> even if you failed it, continue
id nginx || true
chown -R nginx:nginx /usr/share/nginx/html || true
systemctl enable nginx
systemctl start nginx

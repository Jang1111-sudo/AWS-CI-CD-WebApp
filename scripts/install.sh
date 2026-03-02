#!/bin/bash
set -euxo pipefail

#install nginx(if it isn't -> install, if it is -> continue)
dnf -y install nginx nginx-core nginx-filesystem

#ready for web root
mkdir -p /usr/share/nginx/html

#if index.html is directory, remove it
if [ -d /usr/share/nginx/html/index.html]; then
	rm -rf /usr/share/nginx/html/index.html
fi

#ensure /etc/nginx
mkdir -p /etc/nginx

#if there is not mime.types, make
if [ ! -f /etc/nginx/mime.types ]; then
	cat >/etc/nginx/mime.types <<'EOF'
types {
    text/html                             html htm;
    text/css                              css;
    text/xml                              xml;
    image/gif                             gif;
    image/jpeg                            jpeg jpg;
    application/javascript                js;
    application/json                      json;
    application/pdf                       pdf;
    application/octet-stream              bin exe;
    image/png                             png;
    image/svg+xml                         svg;
}
EOF
fi
#start nginx after check 
nginx -t
systemctl enable nginx
systemctl restart nginx

#!/bin/bash
set -e
dnf install -y nginx
systemctl enable nginx
systemctl start nginx

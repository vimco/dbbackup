#!/bin/bash

PACKAGES="python-devel gcc cloog-ppl cpp glibc-devel libgomp glibc-headers mpfr ppl kernel-headers python-pip"
yum -y install $PACKAGES
yum install python-pip
pip install bakthat argparse importlib
yum -y erase $PACKAGES

useradd dbbackup
su dbbackup <<EOF
bakthat configure
bakthat configure_backups_rotation
EOF
#!/bin/bash

PACKAGES="python-devel gcc cloog-ppl cpp glibc-devel libgomp glibc-headers mpfr ppl kernel-headers python-pip"
yum -y install $PACKAGES
yum install python-pip
pip install bakthat argparse importlib
yum -y erase $PACKAGES

getent passwd dbbackup >/dev/null || useradd dbbackup
sudo -u dbbackup bakthat configure
sudo -u dbbackup bakthat configure_backups_rotation

#!/bin/bash

which bakthat > /dev/null 2>&1

if [ $? -ne 0 ]
  then
  PACKAGES="python-devel gcc cloog-ppl cpp glibc-devel libgomp glibc-headers mpfr ppl kernel-headers python-pip"
  yum -y install $PACKAGES
  yum install python-pip
  pip install bakthat argparse importlib
  yum -y erase $PACKAGES

  getent passwd dbbackup >/dev/null || useradd dbbackup
fi

if [ ! -f ~/.bakthat.yml ]
  then
  sudo -u dbbackup bakthat configure
  sudo -u dbbackup bakthat configure_backups_rotation
fi

cp -a dbbackup.sh /usr/local/bin/
cp -a dbrestore.sh /usr/local/bin/

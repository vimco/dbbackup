#!/bin/bash

USER_HOME=/home/dbbackup

which bakthat > /dev/null 2>&1

if [ $? -ne 0 ]
  then
  pushd /tmp
  wget http://mirror-fpt-telecom.fpt.net/fedora/epel/6/i386/epel-release-6-8.noarch.rpm
  rpm -Uvh epel-release-6-8.noarch.rpm
  wget http://www.percona.com/redir/downloads/XtraBackup/LATEST/RPM/rhel6/x86_64/percona-xtrabackup-2.1.8-733.rhel6.x86_64.rpm
  rpm -Uvh percona-xtrabackup-2.1.8-733.rhel6.x86_64.rpm
  popd
  PACKAGES="python-devel gcc cloog-ppl cpp glibc-devel libgomp glibc-headers mpfr ppl kernel-headers python-pip"
  yum -y install $PACKAGES
  # download and install xtradbbackup
  yum -y install python-pip pigz
  pip install bakthat argparse importlib
  yum -y erase $PACKAGES

  getent passwd dbbackup >/dev/null || useradd dbbackup
fi

if [ ! -f $USER_HOME/.bakthat.yml ]
  then
  sudo -u dbbackup bakthat configure
  sudo -u dbbackup bakthat configure_backups_rotation

  cat <<EOL >> $USER_HOME/.bakthat.yml
  plugins_dir: $USER_HOME/.bakthat_plugins/
  plugins: [mp_s3_backend.S3Swapper]
  s3_prefix: /full/$HOSTNAME
EOL
fi

cp -a dbbackup.sh /usr/local/bin/
cp -a dbrestore.sh /usr/local/bin/

mkdir -p $USER_HOME/.bakthat_plugins
cp -a mp_s3_backend.py $USER_HOME/.bakthat_plugins/

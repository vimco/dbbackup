#!/bin/bash

USER_HOME=/home/dbbackup

/bin/ls /etc/debian_version >/dev/null 2>&1
if [ $? -ne 0 ]; then
  OS='redhat'
else
  OS='debian'
fi

install_bakthat() {
  if [ "$OS" == 'debian' ];
  then
    PACKAGES="build-essential python-pip"
    apt-get -y install $PACKAGES pigz
    # download and install xtradbbackup
    pip install bakthat argparse importlib
    apt-get -y remove $PACKAGES
  else
    PACKAGES="python-devel gcc cloog-ppl cpp glibc-devel libgomp glibc-headers mpfr ppl kernel-headers python-pip"
    yum -y install $PACKAGES pigz
    # download and install xtradbbackup
    pip install bakthat argparse importlib
    yum -y erase $PACKAGES
  fi

  getent passwd dbbackup >/dev/null || useradd dbbackup
}

install_xtrabackup() {
  pushd /tmp
  if [ "$OS" == "debian" ]
  then
    wget http://www.percona.com/redir/downloads/XtraBackup/LATEST/deb/wheezy/x86_64/percona-xtrabackup_2.1.8-733-1.wheezy_amd64.deb
    dpkg -i percona-xtrabackup_2.1.8-733-1.wheezy_amd64.deb
    if [ $? -ne 0 ]
    then
      apt-get -fy install
      dpkg -i percona-xtrabackup_2.1.8-733-1.wheezy_amd64.deb
    fi
    rm -f percona-xtrabackup_2.1.8-733-1.wheezy_amd64.deb
  else
    wget http://mirror-fpt-telecom.fpt.net/fedora/epel/6/i386/epel-release-6-8.noarch.rpm
    yum install -y epel-release-6-8.noarch.rpm
    wget http://www.percona.com/redir/downloads/XtraBackup/LATEST/RPM/rhel6/x86_64/percona-xtrabackup-2.1.8-733.rhel6.x86_64.rpm
    yum install -y percona-xtrabackup-2.1.8-733.rhel6.x86_64.rpm
    rm -f percona-xtrabackup-2.1.8-733.rhel6.x86_64.rpm
  fi
  popd
}

which bakthat > /dev/null 2>&1
if [ $? -ne 0 ]; then
  install_bakthat
fi;

which innobackupex > /dev/null 2>&1
if [ $? -ne 0 ]; then
  install_xtrabackup
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

#!/bin/sh

BACKUP_USER=dbbackup

if [ $# -lt 2 ]; then
    echo "Usage : $0 [full|incremental] /path/to/backup_base_dir"
    exit
fi
BACKUP_DIR=$2

FULL_DIR=$(readlink -f $BACKUP_DIR/full)
INCR_DIR=$(readlink -f $BACKUP_DIR/incremental)

# Prepare directories
mkdir -p $FULL_DIR || (echo "Unable to write to $BACKUP_DIR" && exit)
mkdir -p $INCR_DIR
chown -R $BACKUP_USER $BACKUP_DIR
chmod -R 770 $BACKUP_DIR

find_last_full()
{
    LAST_FULL=`find $FULL_DIR -maxdepth 1 -type d | sort | tail -n1`
    if [ ! -d $LAST_FULL ]
	then
	echo "Unable to locate last full backup in $FULL_DIR.  Exiting."
	exit
    fi
}

test_complete_ok()
{
    logfile=shift
    ok=`grep 'completed OK!' $logfile`
    if [ "$ok" = "" ]
      then
      echo "Process did not complete properly.  Check $logfile for errors"
      exit
    fi
}
case $1 in
full)
    logfile=$BACKUP_DIR/`date +%Y%M%d%H%m%s`-full_backup.log
    innobackupex --user=$BACKUP_USER $BACKUP_DIR | tee $logfile
    test_completed_ok $logfile
    find_last_full
    innobackupex --use-memory=1G --apply-log $LAST_FULL
    ;;
incremental)
    logfile=$BACKUP_DIR/`date +%Y%M%d%H%m%s`-incremental_backup.log
    find_last_full
    innobackupex --user=$BACKUP_USER --incremental $INCR_DIR --incremental-basedir=$LAST_FULL --user=$BACKUP_USER | tee $logfile
    test_completed_ok $logfile
    ;;
esac


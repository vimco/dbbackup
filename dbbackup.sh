#!/bin/sh

BACKUP_USER=dbbackup

if [ $# -lt 2 ]; then
    echo "Usage : $0 [full|incremental] /path/to/backup_base_dir"
    exit
fi
BACKUP_DIR=$2

FULL_DIR=$BACKUP_DIR/full
INCR_DIR=$BACKUP_DIR/incremental

# Prepare directories
mkdir -p $FULL_DIR || (echo "Unable to write to $BACKUP_DIR" && exit)
mkdir -p $INCR_DIR
chown -R $BACKUP_USER $BACKUP_DIR
chmod -R 770 $BACKUP_DIR

last_full()
{
    `find $FULL_DIR -type d | sort | tail -n1`
}

case $1 in
full)
    innobackupex --user=$BACKUP_USER $BACKUP_DIR
    LAST_FULL=last_full
    innobackupex --use-memory=1G --apply-log $LAST_FULL
    ;;
incremental)
    LAST_FULL=last_full
    if [ ! -d $LAST_FULL ]
        then
        echo "Unable to locate last full backup in $FULL_DIR.  Exiting."
        exit
    fi
    innobackupex --user=$BACKUP_USER --incremental $INCR_DIR --incremental-basedir=$LAST_FULL --user=$BACKUP_USER
    ;;
esac


# Backup and restore scripts

These scripts assume Percona XtraBackup is already installed.  See:

http://www.percona.com/software/percona-xtrabackup


## dbbackup.sh

Perform full or incremental backups on a database machine

usage: dbbackup.sh <full|incremental> /path/to/backup/dir/base

## dbrestore.sh

Restore a full or incremental backup

usage: dbrestore.sh /path/to/full_backup [/path/to/incremental_backup]

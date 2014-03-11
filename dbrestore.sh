#!/bin/sh

innobackupex --apply-log --redo-only $FULLBACKUP \
 --use-memory=1G --user=USER --password=PASSWORD

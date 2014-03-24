#!/bin/bash

# Find either latest restore target or requested target
if [ $# -lt 1 ]; then
    echo "Usage : $0 [full|incremental] <target>"
    exit
fi

type=$1
target=$2

if [ "$target" == "" ]; then
  target=`bakthat show | head -1`
fi

is_local_target=`echo $target | grep '^/'`
if [ "is_local_target" != "" ]; then
  is_local_target=1
else
  is_local_target=0
fi

should_continue() {
  text=$1
  answer="n"
  printf "$text. Is this ok? <y|N> "
  read answer

  if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
    return
  elif [ "$answer" = "n" ] || [ "$answer" = "N" ] || [ "$answer" = "" ]; then
    echo "Exiting."
    exit
  else
    should_continue "$text"
  fi
}

perform_restore() {
  export TMP=/dbbackup/restore
  mkdir -p $TMP

  if [ $is_local_target -eq 0 ]; then
    echo "Restoring backup from remote location to local"
    bakthat restore $target
    extract_dir=$TMP/`basename $target .tgz`
    tar -xf $TMP/$target -C $extract_dir
    target=$extract_dir
  fi

  should_continue 'In order to continue restoration, the existing mysql data directory must be clean.  Next step is to run `rm -rf /mysql/data`'
  `rm -rf /mysql/data/*`

  case $type in
    full)
      should_continue "About to restore data to target"
      innobackupex --apply-log $target
      innobackupex --copy-back $target

      chown -R mysql /mysql/data
      ;;

    incremental)
      last_full=`find /dbbackup/full -maxdepth 1 -type d | sort | tail -n1`
      innobackupex --apply-log --redo-only $last_full --incremental-dir=$target

      innobackupex --apply-log $last_full
      innobackupex --copy-back $last_full

      chown -R mysql /mysql/data
      ;;
  esac
}

should_continue "About to perform $type restore using $target"
perform_restore

#!/bin/sh

# Find either latest restore target or requested target
if [ $# -lt 2 ]; then
    echo "Usage : $0 [full|incremental] <target>"
    exit
fi

type=$1
target=$2

if [ "$target" -eq ""]; then
  target=`bakthat show | head -1`
fi

is_local_target=`echo $target | grep '^/'`
if [ "is_local_target" -ne "" ];
  is_local_target=1
else
  is_local_target=0
fi

should_continue() {
  text=$1
  answer="n"
  echo "$text. Is this ok? <y|N> "
  read answer

  if [ "$answer" -eq "y" || "$answer" -eq "Y" ]; then
    return
  elif [ "answer" -eq "n" || "$answer" -eq "N"]; then
    echo "Ok - Exiting!"
  else
    should_continue()
  fi
}

should_continue("About to perform $type restore using $target")
perform_restore()

perform_restore() {
  export TMP=/dbbackup/restore
  mkdir -p $TMP

  if [ $is_local_target == 0 ]; then
    echo "Restoring backup from remote location to local"
    bakthat restore $target
    extract_dir=$TMP/`basename $target .tgz`
    tar -xf $TMP/$target -C $extract_dir
    target=$extract_dir
  fi

  case $type in
    full)
      should_continue("In order to continue restoration, the existing mysql data directory must be clean.  Next step is to run `rm -rf /mysql/data`")
      `rm -rf /mysql/data/*`

      should_continue("About to restore data to target")
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

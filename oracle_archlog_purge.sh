#!/bin/env sh

## It's to purge Oracle archive log in Linux Platform
## 2 parameter - instance name and archive log retention

## Required
##  cronjob run oracle user account
## cronjob
##  10 08 * * * $HOME/oracle_archlog_purge.sh -i <SID> -r 7 > /dev/null

## Function List
function info_msg  { echo "$(date '+%D %T'): [INFO] $1"| tee -a ${LOGFILE}; }
function warn_msg  { echo "$(date '+%D %T'): [WARNING] $1"| tee -a ${LOGFILE}; }
function error_msg  { echo "$(date '+%D %T'): [ERROR] $1"| tee -a ${LOGFILE}; }
function usage { echo "ERROR! Usage: ${0##*/} -i <ORACLE_SID> -r <RETENTION :default 30 days> "; }

## variables
PP=$(cd $(dirname $0) && pwd)
PN=$(basename $0 ".sh")
LOGFILE=$PP/$PN.log
SQLFILE=$PP/$PN.sql
TMPFILE=$PP/$PN.tmp

######### Parameter define ################
while getopts i:r: next; do
  case $next in
    i) SID=$OPTARG;;
    r) RET=$OPTARG;;
    *) usage ; exit 1 ;;
  esac
done

## retention and instance name
RET=${RET:-30}
[[ -z $SID ]] && error_msg "ORACLE SID is null. Exit.." && exit 1

## Judge Instance is running and archive log mode
[[ -z $(ps -ef|grep ora_smon_$SID|grep -v grep) ]] && error_msg "Instance $SID not running. Exit .." && exit 1
[[ -z $(ps -ef|grep ora_arc0_$SID|grep -v grep) ]] && warn_msg "Instance $SID not archivelog mode. Exit .." && exit 1

## Oracle environment setting
export ORACLE_SID=$SID
export ORACLE_HOME=$(/usr/local/bin/dbhome $SID)
[ ! -d $ORACLE_HOME ] && warn_msg "Not found Oracle Home. Exit.." && exit 1

## SQL File
cat > $SQLFILE <<EOF
archive log list
exit
EOF

## Get archive log path
$ORACLE_HOME/bin/sqlplus '/ as sysdba' < $SQLFILE >$TMPFILE
ARC_PATH=$(cat $TMPFILE|grep "Archive destination"|sed 's/Archive destination//g'|sed 's/ *//g')
## For recovery file dest path
if [ $ARC_PATH == "USE_DB_RECOVERY_FILE_DEST" ]; then
  echo "set head off" > $SQLFILE
  echo "select value from v\$parameter where name='db_recovery_file_dest';" >> $SQLFILE
  ARC_PATH=$($ORACLE_HOME/bin/sqlplus -S '/ as sysdba' < $SQLFILE)
fi
## if it's filesystem path
if [ -d $ARC_PATH ] ; then
  if [ $(find $ARC_PATH/ -mtime +$RET -type f |wc -l ) -ge 1 ]; then
    info_msg "Start to to purge archivelog file with retention=$RET days under $ARC_PATH"
    find $ARC_PATH/ -mtime +$RET -type f |xargs ls -l >> $LOGFILE
    find $ARC_PATH/ -mtime +$RET -type f|xargs rm -f 2>>$LOGFILE
  else
    info_msg "No files need be purged(retention=$RET days)"
  fi
## For ASM path
elif [ $(echo $ARC_PATH|awk '{if(substr($0,1,1)=="+") print 1}') == 1 ]; then
  info_msg "Start to to purge archivelog file with retention=$RET days under $ARC_PATH"
  echo "delete noprompt archivelog until time 'sysdate -$RET';" > $SQLFILE
  $ORACLE_HOME/bin/rman target / cmdfile=$SQLFILE append log=$LOGFILE 2>>$LOGFILE
else
  warn_msg "Can not find archive log path"
fi
  
## Remove temporary file
[ -f $TMPFILE ] && rm $TMPFILE
[ -f $SQLFILE ] && rm $SQLFILE 

## Rotate logfile 
MAX_LOG_SIZE=10240000 # 10MB
if [ $(ls -l $LOGFILE|awk '{print $5}') -ge $MAX_LOG_SIZE ]; then
  info_msg "Cutting off logfile $LOGFILE"
  mv $LOGFILE $LOGFILE.old || warn_msg "Move file $LOGFILE failure"
fi

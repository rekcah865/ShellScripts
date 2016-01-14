#!/bin/env sh

## It's to purge PostgreSQL log in Linux Platform
## 2 parameter - PG home and log keep retention

## Required
##  cronjob run postgres user account
## cronjob
##  10 08 * * * $HOME/cronjob/pglog_purge.sh -h /u01/app/postgres/9.3.5 -r 7 > /dev/null

## Function List
function info_msg  { echo "$(date '+%D %T'): [INFO] $1"| tee -a ${LOGFILE}; }
function warn_msg  { echo "$(date '+%D %T'): [WARNING] $1"| tee -a ${LOGFILE}; }
function error_msg  { echo "$(date '+%D %T'): [ERROR] $1"| tee -a ${LOGFILE}; }
function usage { echo "ERROR! Usage: ${0##*/} -h <PostgreSQL Home Path :default /u01/app/postgres/9.3.5> -r <RETENTION :default 30 days> "; }

## variables
PP=$(cd $(dirname $0) && pwd)
PN=$(basename $0 ".sh")
LOGFILE=$PP/$PN.log
SQLFILE=$PP/$PN.sql
#TMPFILE=$PP/$PN.tmp

######### Parameter define ################
while getopts h:r: next; do
  case $next in
    h) PGHOME=$OPTARG;;  
    r) RET=$OPTARG;;
    *) usage ; exit 1 ;;
  esac
done

## retention
RET=${RET:-30}
PGHOME=${PGHOME:-/u01/app/postgres/9.3.5}	

## Judge Instance is running 
[[ -z $(ps -ef|grep /postgres|grep -v grep) ]] && error_msg "PostgreSQL DB not running. Exit .." && exit 1

## PostgreSQL environment setting
export PGHOME
[ ! -d $PGHOME ] && warn_msg "Not found PostgreSQL Home. Exit.." && exit 1
export PATH=$PGHOME/bin:$PATH
export PGDATA=$PGHOME/data

## Initial SQL file
cat > $SQLFILE <<EOF
select a.setting||'/'||b.setting from pg_settings a, pg_settings b where a.name='data_directory' and b.name='log_directory';
EOF

## Get pg log path
LOG_PATH=$($PGHOME/bin/psql -t -f $SQLFILE |tr -d '\n',' ')
[ ! -d $LOG_PATH ] && warn_msg "Not found PostgreSQL Log directory. Exit.." && exit 1

if [ $(find $LOG_PATH/ -mtime +$RET -type f |wc -l) -ge 1 ]; then
    info_msg "Start to to purge pglog file with retention=$RET days under $LOG_PATH"
    find $LOG_PATH/ -mtime +$RET -type f |xargs ls -l >> $LOGFILE
    find $LOG_PATH/ -mtime +$RET -type f|xargs rm -f 2>>$LOGFILE
else
    info_msg "No files need be purged(retention=$RET days)"
fi

## Remove temporary file
#[ -f $TMPFILE ] && rm $TMPFILE
[ -f $SQLFILE ] && rm $SQLFILE 

## Rotate logfile 
MAX_LOG_SIZE=10240000 # 10MB
if [ $(ls -l $LOGFILE|awk '{print $5}') -ge $MAX_LOG_SIZE ]; then
  info_msg "Cutting off log file $LOGFILE"
  mv $LOGFILE $LOGFILE.old || warn_msg "Move file $LOGFILE failure"
fi

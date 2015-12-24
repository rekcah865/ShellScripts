#!/bin/env sh

## It's to logical backup MySQL database with mysqldump command on remote backup server
## It's evaludated in Linux 86 Platform(CentOS 6, RHEL 6)
## It run daily(cronjob) and Keep backup(SQL file) for one week 
##
## You can set cronjob as below
## 50 07 * * * $HOME/mysqldump_bkp.sh 

VERSION=1.0

PP=$(cd $(dirname $0) && pwd)
PN=$(basename $0 ".sh")
LOG=$PP/$PN.log
## backup destination path
BKPDIR=$PP

function info_msg  { echo "$(date '+%D %T'): [INFO] $1"| tee -a ${LOG}; }
function warn_msg  { echo "$(date '+%D %T'): [WARNING] $1"| tee -a ${LOG}; }
function error_msg  { echo "$(date '+%D %T'): [ERROR] $1"| tee -a ${LOG}; }

function terminate_script()
{
  error_msg "SIGINT caught."
  exit 1
}

trap 'terminate_script' SIGINT

cd $PP || exit

## Check related command 
BINARYS=(/usr/bin/mysql /usr/bin/mysqldump mailx)
for BINARY in "${BINARYS[@]}" ; do
  if [ ! "$(command -v "$BINARY")" ]; then
    error_log "$BINARY is not installed. Install it and try again"
    exit
  fi
done

## DB Configuration
export MYUSER=root
export MYPASSWORD=root123
DUMPOPS=" --single-transaction "
DBS=

## Mail Configuration
MAIL_SENDER=
MAIL_RCV=
MAIL_SUBJECT=

for DBSERVER in ssfiswebdb
do
  DBS=$(/usr/bin/mysql -h $DBSERVER -u $MYUSER -p$MYPASSWORD -Bse 'show databases')
  info_msg "Get databse list - $DBS for $DBSERVER"

  info_msg "Start to do mysqldump backup for $DBSERVER"
  for DB in ${DBS[@]} ; do
    info_msg "-- Backup $DB's data start"
      /usr/bin/mysqldump -u $MYUSER -h $DBSERVER $DUMPOPS $DB -p$MYPASSWORD > $BKPDIR/$DBSERVER-${DB}-$(date +%a).sql 2>>$LOG
      info_msg "-- Backup $DB's data end"
    done
  info_msg "End to do pg_dump backup for $DBSERVER"
done

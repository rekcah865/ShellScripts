#!/bin/env sh

## It's to RMAN Full Database backup
## Requirement
## 	Run cronjob under oracle account
## cronjob
##	00 07 * * 1 /mnt/bkup/prod/ORACLEDB/rmanfulldb_bkp.sh -i <SID> -d <path> -p <parallel>

VERSION=1.0
HOST=$(hostname)

PP=$(cd $(dirname $0) && pwd)
PN=$(basename $0 ".sh")
LOGFILE=$PP/$PN.log
TMPFILE=$PP/$PN.tmp.$$

### Function define 
function info_msg  { echo "$(date '+%D %T'): [INFO] $1"| tee -a ${LOGFILE}; }
function warn_msg  { echo "$(date '+%D %T'): [WARNING] $1"| tee -a ${LOGFILE}; }
function error_msg  { echo "$(date '+%D %T'): [ERROR] $1"| tee -a ${LOGFILE}; }
function usage { echo "ERROR! Usage: ${0##*/} -i <ORACLE_SID> -d <DESTINATION :default /mnt/bkup/prod/ORACLEDB/> -p <PARALLEL: default 2>"; }
function terminate_script { error_msg "SIGINT caught."; exit; }

trap 'terminate_script' SIGINT

######### Parameter define ################
while getopts i:d:p: next; do
  case $next in
    i) SID=$OPTARG;;
    d) DESTINATION=$OPTARG;;
    p) PARALLEL=$OPTARG;;
    *) usage ; exit 1 ;;
  esac
done

## Instance name and Backup Destination
DESTINATION=${DESTINATION:-/mnt/bkup/prod/ORACLEDB}
[[ -z $SID ]] && error_msg "ORACLE SID is null. Exit.." && exit 1

## Judge Instance is running and if it's archive log mode during instance running
if [[ -z $(ps -ef|grep ora_smon_$SID|grep -v grep) ]] ; then
	info_msg "Instance $SID not running. Can do cold backup " 
else
	[[ -z $(ps -ef|grep ora_arc0_$SID|grep -v grep) ]] && warn_msg "Instance $SID not archivelog mode. Exit .." && exit 1
fi

## Get Oracle Software information
export ORACLE_SID=$SID
export ORACLE_HOME=$(/usr/local/bin/dbhome $SID)
[ ! -d $ORACLE_HOME ] && warn_msg "Not found Oracle Home. Exit.." && exit 1

## Judge Backup destination
[ ! -w $DESTINATION ] && error_msg "Not write privis for $DESTINATION. Exit.." && exit 1
BKPDIR=$DESTINATION/${HOST}_${ORACLE_SID}
[ ! -d $BKPDIR ] && mkdir -p $BKPDIR && info_msg "Create folder $BKPDIR"

## Judge command existed
BINARYS=($ORACLE_HOME/bin/rman mailx egrep)
for BINARY in "${BINARYS[@]}" ; do
        if [ ! "$(command -v "$BINARY")" ]; then
                error_log "$BINARY is not installed. Install it and try again"
                exit
        fi
done

## DB Configuration
USR=
PASSWD=

## RMAN backup configuration
PARALLEL=${PARALLEL:-2}
MAXPIECESIZE=8G
OPTIONS=" nocatalog log $TMPFILE "

## Alert Mail Configuration
MAIL_SENDER=""
MAIL_RCV=""
MAIL_SUBJECT="Oracle RMAN Full $ORACLE_SID DB backup Error on $HOST"

info_msg "Start to do RMAN full db backup for $ORACLE_SID on $HOST"
$ORACLE_HOME/bin/rman target $USR/$PASSWD $OPTIONS <<EOF
	## Configuration 
	CONFIGURE RETENTION POLICY TO REDUNDANCY 2;
	CONFIGURE CONTROLFILE AUTOBACKUP ON;
	CONFIGURE CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE DISK TO '$BKPDIR/cf_%F';
	CONFIGURE DEVICE TYPE DISK PARALLELISM $PARALLEL BACKUP TYPE TO BACKUPSET;
	CONFIGURE CHANNEL DEVICE TYPE DISK FORMAT '$BKPDIR/db_%d_S_%s_P_%p_T_%t' MAXPIECESIZE $MAXPIECESIZE;
	CONFIGURE SNAPSHOT CONTROLFILE NAME TO '$BKPDIR/snapcf_gpic.f';	

	## Database Backup
  	backup as backupset database plus archivelog delete input;
	
	## Backup Maintenance
  	Crosscheck archivelog all;
  	delete noprompt expired archivelog all;
  	crosscheck backup;
  	delete noprompt expired backup;
  	delete noprompt obsolete;
	
EOF
if [[ -z $(cat $TMPFILE |egrep -i '(ORA-|ERROR|RMAN-)') ]]; then
	info_msg "Succeed to RMAN backup for $ORACLE_SID on $HOST (size=$(du -sh $BKPDIR|awk '{print $1}'))"
else
	warn_msg "Error while rman backup, send to $MAIL_RCV"
	cat $TMPFILE |mailx -s "$MAIL_SUBJECT" $MAIL_RCV || cat $TMPFILE >> $LOGFILE
fi

## Remove temporary file
[ -f $TMPFILE ] && rm $TMPFILE

## Logrotate logfile 
MAX_LOG_SIZE=10240000 # 10MB
if [ $(ls -l $LOGFILE|awk '{print $5}') -ge $MAX_LOG_SIZE ]; then
  info_msg "Cutting off logfile $LOGFILE"
  mv $LOGFILE $LOGFILE.old || warn_msg "Move file $LOGFILE failure"
fi

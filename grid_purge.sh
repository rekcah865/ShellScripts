#!/bin/env ksh

################ Description: 
#	It's to pureg log,trace,dump file in Oracle GI on Linux/Unix Platform
#	Default retention: 60 days

################ Requirement:
#	It's running under grid(or root) user who has enough to access the related file
#	Set it cronjob - interval is 10 minutes

################ History
## v1.0		Wei.W.Shen	Oct 8 2015			Creation

################ Cronjob
## Linux
# 0 16 * * 1-5 $HOME/cronjob/grid_purge.sh >/dev/null
# 0 16 * * * 1-5 /u01/usr/grid/cronjob/grid_purge.sh >/dev/null
## AIX
## 0 16 * * 1-5 /u01/usr/grid/cronjob/grid_purge.sh >/dev/null
#

######### Function define ################
function debug_msg  { echo "$(date '+%D %T'): [DEBUG] $1"| tee -a ${LOGFILE}; }
function info_msg  { echo "$(date '+%D %T'): [INFO] $1"| tee -a ${LOGFILE}; }
function warn_msg  { echo "$(date '+%D %T'): [WARNING] $1"| tee -a ${LOGFILE}; }
function error_msg  { echo "$(date '+%D %T'): [ERROR] $1"| tee -a ${LOGFILE}; }

## Variable define
PP=$(cd $(dirname $0) && pwd)
PN=$(basename $0 ".sh")
HOST=$(hostname)
RETENTION=60 ## 60 days
LOGFILE=$PP/$PN.log

## For Oracle GI HOME and SID
ORACLE_BASE=/u01/app/grid
ORACLE_SID=+ASM

## Check Command existed
which find > /dev/null 2>>$LOGFILE && which xargs >/dev/null 2>>$LOGFILE
if [ $? -ne 0 ]; then
	error_msg "find or xargs is required"
	exit 1
fi

## Define the folder and file format
DIR="$ORACLE_BASE/diag $ORACLE_BASE/product"
SUFS="*.trc *.trm *.aud *.xml"
for SUF in $SUFS
do
	CNT=$(find $DIR -type f -mtime +$RETENTION -name "$SUF" 2>>$LOGFILE|wc -l)
	if [ $CNT -gt 0 ]; then
		info_msg "Start to remove $CNT files in $DIR on $HOST with $SUF (Timestamp > $RETENTION days)"
		find $DIR -type f -mtime +$RETENTION -name "$SUF" 2>>$LOGFILE |xargs -r rm -f 2>>$LOGFILE
		info_msg "End to remove $CNT files in $DIR on $HOST with $SUF (Timestamp > $RETENTION days)"
	else
		info_msg "No matched files found in $DIR on $HOST with $SUF (Timestamp > $RETENTION days)"
	fi
done

## Cut log file if it more than 10MB
if [ $(ls -l $LOGFILE|awk '{print 5}') -gt 102400000 ]; then
	info_msg "$LOGFILE Size($(ls -l $LOGFILE|awk '{print 5}')) is more than 10MB and cut-off it"
	mv $LOGFILE $LOGFILE.old
fi

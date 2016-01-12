#!/bin/env ksh
#This script use to calculate Oracle table space and try send out alert
#when it detect table space getting full.
#It computes the tbs size with last 8 hours to forecast 24 hours 
#
#Script Name    :       tbs_forecast.sh
#Create Date    :       Sep 22,2015
#Author         :       Wei.W.Shen
#Version        :       1.0
#History        :       Sep 22,2015 Shen Wei	Creation

#Cron job item format :
#5 8,16 * * * $SEA_HOME/cronjob/tbs_forecast/tbs_forecast.sh 
#which the < 8,16 > must be same as < $FT,$LT >

#Script Requirement :
#Please make sure you cron job & test account able to logon oracle database appropriate
#The oracle database related table read privilege required.
#The $FT & $LT must be configure appropriate.

######### Function define ################
function debug_msg  { echo "$(date '+%D %T'): [DEBUG] $1"| tee -a ${LOGFILE}; }
function info_msg  { echo "$(date '+%D %T'): [INFO] $1"| tee -a ${LOGFILE}; }
function warn_msg  { echo "$(date '+%D %T'): [WARNING] $1"| tee -a ${LOGFILE}; }
function error_msg  { echo "$(date '+%D %T'): [ERROR] $1"| tee -a ${LOGFILE}; }

function usage { echo "ERROR! Usage: ${0##*/} -u [Oracle userid] -i [Oracle Sid]" ; }

## Collect tbs size status
function tbs_size {
	info_msg "Start to get tbs size "
	$ORACLE_HOME/bin/sqlplus -s $ORACLE_USR/$ORACLE_PASSWD << EOF
	col tablespace_name format A20
	set heading off
	set feedback off
	set pages 100
	set linesize 60
	spool $OUTFILE
	select tablespace_Name,round(sum(bytes)/1024/1024) usedsize,decode(autoextensible,'YES',round(sum(maxbytes)/1024/1024),round(sum(bytes)/1024/1024)) maxsize from dba_data_files group by tablespace_Name,autoextensible 
	union all
	select tablespace_Name,round(sum(bytes)/1024/1024) usedsize,decode(autoextensible,'YES',round(sum(maxbytes)/1024/1024),round(sum(bytes)/1024/1024)) maxsize from dba_temp_files group by tablespace_Name,autoextensible 
	order by 1;
	spool off
	exit;
EOF
	cat $OUTFILE >> $LOGFILE
	info_msg "Successful get tbs size - usedsize,maxsize"
}

## Compare size on increased and extensible 
function compare_size {
	if [ -f $LFILE -a -f $FFILE ]; then
		cat $LFILE $FFILE|sed '/^$/d'|sort|uniq|awk '{print $1}' > $TMPFILE.tbs
		while read TBS
		do
			FSIZE=$(cat $FFILE|grep ^$TBS|awk '{print $2}')
			LSIZE=$(cat $LFILE|grep ^$TBS|awk '{print $2}')
			MSIZE=$(cat $LFILE|grep ^$TBS|awk '{print $3}')
			FREE=$(expr $MSIZE - $LSIZE)
			GAP_8=$(expr $LSIZE - $FSIZE)
			GAP_24=$(expr $GAP * 3)
			if [ $FREE -lt ${GAP_24} ]; then
				MAIL_FLAG=1
				info_msg "$TBS has ${FREE}MB expansion and ${GAP_24} requirement in next 24 hours"
				echo "$TBS\t$FREE\t${GAP_24}\t" >> $MAILFILE.tmp
			fi
		done < $TMPFILE.tbs		
	else
		warn_msg "$LFILE or $FFILE not found"
		exit 3
	fi
}

## Send alert mail
function send_alert {
    # Send the mail , get mail related content by variables
    # $1 - mail contents file
    # $2 - mail subjects
	# $3 - mail sender
    # $4 - mail receiver

    if [ $# -eq 4 ]
    then
        cat $1|mailx -s "$2" -r $3 "$4"
        if [ $? -ne 0 ]; then
            error_msg "function send_alert executing error on $PN"
            return 1
        fi
    else
        error_msg "Wrong parameter with send_alert function on $PN"
        return 1
    fi
    return 0
}

######### Parameter define ################
while getopts u:i: next; do
    case $next in
        u)
            ORAUSER=$OPTARG
            ;;		
        i)
            SID=$OPTARG
            ;;
        *)
            Usage
            exit 0
            ;;
    esac
done

######### Variable define ################
export PP=$(dirname ${0})
export PN=$(basename "$0" ".sh")
export HOST=$(hostname)

export LOGFILE=${PP}/${PN}.log
export TMPFILE=$PP/$PN.tmp

## For Oracle Environment
export ORACLE_SID=${SID:?"ERROR! Usage: ${0##*/} -u [Oracle userid] -i [Oracle Sid]"}
export ORACLE_USR=${ORAUSER:?"ERROR! Usage: ${0##*/} -u [Oracle userid] -i [Oracle Sid]"}
export ORACLE_HOME=$(/usr/local/bin/dbhome ${ORACLE_SID})
export ORACLE_PASSWD=$(/usr/local/bin/orapass ${ORACLE_USR})

if [ -z "$ORACLE_HOME" ]; then
	warn_msg "Could not get Oracle home for $ORACLE_SID"
	exit 1
fi
if [ -z "$ORACLE_PASSWD" ]; then
	warn_msg "Could not get Oracle password for $ORACLE_USR"
	exit 1
fi

## Collect time configuration
FT="08" # First time
LT="16" # Last time
## Temporary file store tbs name and size 
FFILE=$PP/$PN.FT
LFILE=$PP/$PN.LT
[ $(date +%H) == $FT ] && OUTFILE=$FFILE
[ $(date +%H) == $LT ] && OUTFILE=$LFILE
## If it's not defined time, skip it.
if [ $(date +%H) != $FT -a $(date +%H) != $LT ]; then
	warn_msg "Current hour is not $FT and $LT, so skip it "
	exit 2
fi

## Mail alert configuration
MAIL_FLAG=0
MAIL_SENDER="Notice@xxx.com"
MAIL_TITLE="$ORACLE_SID DB Tablespaces Will Be Full in Next 24 Hours on $HOST"
MAIL_RCV="wei.w.shen@xxx.com"
export MAILFILE=${PP}/${PN}.mail

## Get tbs size and store it on temporary file
tbs_size

## Compare tbs size if it's last time
[ $(date +%H) == $LT ] && compare_size

## If its result is yes, send alert mail out
if [ $MAIL_FLAG -eq 1 ]; then
	echo "TABLESPACE\tFREE_EXTENSIBLE_SIZE(MB)\tREQUIREMENT(MB)\t" > $MAILFILE
	cat $MAILFILE.tmp >> $MAILFILE
	send_alert $MAILFILE ${MAIL_TITLE} ${MAIL_SENDER} ${MAIL_RCV}
fi

## Clean temporary files
[ -f $MAILFILE.tmp ] && rm $MAILFILE.tmp
[ -f $MAILFILE ] && rm $MAILFILE
[ -f $TMPFILE.tbs ] && rm $TMPEFILE.tbs

## Archive log file (more than 100MB)
if [ $(ls -l $LOGFILE|awk '{print 5}') -gt 1024000000 ]; then
	mv $LOGFILE $LOGFILE.old
fi

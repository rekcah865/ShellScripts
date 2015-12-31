#!/bin/env ksh

## Description: 
#	It's to monitor user cronjob running status on Linux Platform
## Requirement:
#	It's running under root who has enough to access the file under /var/spool/mail
#	Set it cronjob - interval is 10 minutes
## Cronjob
# */10 * * * * /usr/local/bin/cron_check.sh >/dev/null
#
#
##

## Variable define
PP=$(dirname $0)
PN=$(basename $0 ".sh")
HOST=$(hostname)
CRONDIR=/var/spool/mail
INTERVAL=10
VARDIR=/tmp
PARFILE=$PP/$PN.pattern
MAIL_RCV="XXX"

## error pattern key words
cat > $PARFILE << EOF
standard error
not found
not set
No such file
bad interpreter
cannot stat
Syntax error
Specify a parameter with this command.
Cannot Find
timed out
exiting
ERROR at
ORA-
cannot open
EOF

## judge whether it's root 
if [ "$(whoami)" != "root" ]; then
	echo "$PN would be running under root"
	exit 1
fi

if [ ! -d $CRONDIR ]; then
	echo "Directory $CRONDIR not found"
	exit 2
fi

## egrep and mailx command is required
which egrep > /dev/null 2>&1 && which mailx > /dev/null 2>&1
if [ $? -ne 0 ]; then
	echo "egrep is required"
	exit 3
fi

## Find whether it exists spool file be changed in $INTERVAL minutes
CNT=$(find $CRONDIR -type f -mmin -$INTERVAL|wc -l)
if [ $CNT -gt 0 ]; then
	for ITEM in $(find $CRONDIR -type f -mmin -$INTERVAL)
	do
		#echo $ITEM
		## Get the file size
		SIZE1=$(ls -l $ITEM|awk '{print $5}')
		## 2 temp file - 1:store the file size, 2:content since last time
        	TEMPF1=$VARDIR/$PN.1.$(echo $ITEM |tr -s "/" "~")
        	TEMPF2=$VARDIR/$PN.2.$(echo $ITEM |tr -s "/" "~")

		if [ ! -f "$TEMPF1" ];then
            		echo $SIZE1 >$TEMPF1
        	else
            		read SIZE2 <$TEMPF1
            		if [[ $SIZE1 -ne $SIZE2 ]]; then
                		rm $TEMPF2 >/dev/null 2>&1
                		if [[ $SIZE1 -gt $SIZE2 ]];then
                    			NEWC=$(expr $SIZE1 - $SIZE2)
                    			tail -${NEWC}c $ITEM >$TEMPF2
                	else
                    		cat $ITEM >$TEMPF2
			fi
			## Initiate the KEYS, FLAG
                	FLAG=0; KEYS=""
			egrep -i -s -f $PARFILE $TEMPF2 >/dev/null 2>&1
			if [ $? -eq 0 ]; then
				while read ERRKEY
				do
                       	 		grep -i "$ERRKEY" $TEMPF2 >/dev/null 2>&1
                        		if [ $? -eq 0 ];then
                            			FLAG=1
                            			KEYS=$(echo "$ERRKEY,$KEYS")
                        		fi
                    		done < $PARFILE
				## If exist error key in out file of cron, it send mail out
                    		if [ "$FLAG" == "1" ]; then
                        		cat $TEMPF2|mailx -s "$(basename $ITEM) Cronjob running abnormal on $HOST($KEYS)" $MAIL_RCV
                    		fi
			fi
			##Clean up the var FLAG, KEYS
			FLAG=0;	KEYS=""
		fi
       	fi
        echo $SIZE1 >$TEMPF1
    done
fi

## Remove the temp pattern file
[ -f $PARFILE ] && rm $PARFILE


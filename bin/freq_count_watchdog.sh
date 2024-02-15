#!/bin/bash

if [ "$UID" -ne 0 ]; then
	echo "This script has to be run as root."
	exit
fi

# Vars
LBPCONFIGDIR=$(perl -e 'use LoxBerry::System; print $lbpconfigdir; exit;')
LBPBINDIR=$(perl -e 'use LoxBerry::System; print $lbpbindir; exit;')
PLUGINNAME=$(perl -e 'use LoxBerry::System; print $lbpplugindir; exit;')
JSONFILE=$(jq -r '.filename' $LBPCONFIGDIR/plugin.json)
TOPIC=$(jq -r '.topic' $LBPCONFIGDIR/plugin.json)
UDPINPORT=$(jq -r '.Mqtt.Udpinport' $LBSCONFIG/general.json)
FAILSTARTS=0
LAST=0
NEWDATA=""
OLDDATA=""

# Function when exiting
function cleanup {
	LOGEND
}
trap cleanup EXIT

# Create a new entry for the logfile (for logmanager)
. $LBHOMEDIR/libs/bashlib/loxberry_log.sh
PACKAGE=$PLUGINNAME
NAME=freq_count_watchdog
LOGDIR=$LBPLOG/$PLUGINNAME
STDERR=1

LOGSTART "FREQ_COUNT - Watchdog..."
LOGOK "FREQ_COUNT - Watchdog..."

while true
do

	NOW=$(date +%s)

	# Check if all services are running
	if ! pgrep -f freq_count_1 > /dev/null 2>&1 ; then
		LOGWARN "FREQ_COUNT Daemon is not running. That's not good. Restarting..."
		$LBPBINDIR/freq_count_helper.sh start
		sleep 2
		let "FAILSTARTS+=1"
	else
		FAILSTARTS=0
	fi
	if [ $FAILSTARTS -gt 10 ]; then
		LOGCRIT "FREQ_COUNT Daemon is not running. I tried to start it 10 times without success. Giving up. Check logs for error messages."
		touch $LBPCONFIGDIR/daemon_stopped.cfg
		exit 1
	fi

	# Check for new data and send it to Broker
	NEWDATA=$(cat $JSONFILE)
	if [ "$NEWDATA" != "$OLDDATA" ]; then
		LOGDEB "New data found: publish $TOPIC/data $NEWDATA"
		echo "publish $TOPIC/data $NEWDATA" > /dev/udp/127.0.0.1/$UDPINPORT
		echo "publish $TOPIC/last $NOW" > /dev/udp/127.0.0.1/$UDPINPORT
		OLDDATA=$NEWDATA
	fi

	# Keepalive
	let "TIMEDIFF=$NOW-$LAST"
	if [ $TIMEDIFF -gt 59 ]; then
		echo "publish $TOPIC/keepalive $NOW" > /dev/udp/127.0.0.1/$UDPINPORT
		LAST=$NOW
	fi

	sleep 1

done

exit

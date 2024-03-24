#!/bin/bash

if [ "$UID" -ne 0 ]; then
	echo "This script has to be run as root."
	exit
fi

# Vars
LBPCONFIGDIR=$(perl -e 'use LoxBerry::System; print $lbpconfigdir; exit;')
LBPBINDIR=$(perl -e 'use LoxBerry::System; print $lbpbindir; exit;')
PLUGINNAME=$(perl -e 'use LoxBerry::System; print $lbpplugindir; exit;')

# Create a new entry for the logfile (for logmanager)
. $LBHOMEDIR/libs/bashlib/loxberry_log.sh
PACKAGE=$PLUGINNAME
NAME=freq_count_helper
LOGDIR=$LBPLOG/$PLUGINNAME
STDERR=1

case "$1" in

	start)

	LOGSTART "FREQ_COUNT - START Daemon..."

	if [ -e "$LBPCONFIGDIR/daemon_stopped.cfg" ]; then
		rm $LBPCONFIGDIR/daemon_stopped.cfg
	fi

	JSONFILE=$(jq -r '.filename' $LBPCONFIGDIR/plugin.json)
	TEST=$(jq -r '.test' $LBPCONFIGDIR/plugin.json)
	SAMPLERATE=$(jq -r '.samplerate' $LBPCONFIGDIR/plugin.json)
	if [ $SAMPLERATE -lt 1 ]; then
		SAMPLERATE=1
	elif [ $SAMPLERATE -gt 10 ]; then
		SAMPLERATE=10
	fi
	REFRESHRATE=$(jq -r '.refreshrate' $LBPCONFIGDIR/plugin.json)
	if [ $REFRESHRATE -lt 1 ]; then
		REFRESHRATE=1
	elif [ $REFRESHRATE -gt 30 ]; then
		REFRESHRATE=30
	fi
	let REFRESHRATE=$REFRESHRATE*10
	FC1=$(jq -r '.fc1' $LBPCONFIGDIR/plugin.json)
	if [ $FC1 -gt 0 ]; then
		GPIO="$GPIO $FC1"
	fi
	FC2=$(jq -r '.fc2' $LBPCONFIGDIR/plugin.json)
	if [ $FC2 -gt 0 ]; then
		GPIO="$GPIO $FC2"
	fi
	FC3=$(jq -r '.fc3' $LBPCONFIGDIR/plugin.json)
	if [ $FC3 -gt 0 ]; then
		GPIO="$GPIO $FC3"
	fi
	FC4=$(jq -r '.fc4' $LBPCONFIGDIR/plugin.json)
	if [ $FC4 -gt 0 ]; then
		GPIO="$GPIO $FC4"
	fi
	FC5=$(jq -r '.fc5' $LBPCONFIGDIR/plugin.json)
	if [ $FC5 -gt 0 ]; then
		GPIO="$GPIO $FC5"
	fi
	VERBOSE=""
	if [ $LOGLEVEL -gt 6 ]; then
		VERBOSE="-v"
	fi
	pkill -f "freq_count_1"
	sleep 1
	LOGINF "Command: $LBPBINDIR/freq_count_1 $GPIO -r$REFRESHRATE -s$SAMPLERATE $TEST -f $JSONFILE $VERBOSE >> $FILENAME"
	$LBPBINDIR/freq_count_1 $GPIO -r$REFRESHRATE -s$SAMPLERATE $TEST -f $JSONFILE $VERBOSE >> $FILENAME &
	sleep 1
	if pgrep -f "freq_count_1" > /dev/null 2>&1 ; then
		LOGOK "FREQ_COUNT Daemon started successfully."
	else
		LOGERR "FREQ_COUNT Daemon could't be started."
	fi
	if pgrep -f "freq_count_watchdog.sh" > /dev/null 2>&1 ; then
		LOGOK "FREQ_COUNT Watchdog is running. Fine."
	else
		LOGINF "FREQ_COUNT Watchdog isn't running. Also starting the Watchdog."
		LOGINF "Command: $LBPBINDIR/freq_count_watchdog.sh"
		cd $LBPBINDIR && $LBPBINDIR/freq_count_watchdog.sh &
	fi
	;;

	stop)

	LOGSTART "FREQ_COUNT - STOP Daemon..."

	touch $LBPCONFIGDIR/daemon_stopped.cfg

	pkill -f "freq_count_watchdog.sh"
	pkill -f "freq_count_1"
	sleep 1
	if pgrep -f "freq_count_1" > /dev/null 2>&1 ; then
		LOGERR "FREQ_COUNT Daemon could't be stopped."
	else
		LOGOK "FREQ_COUNT Daemon stopped successfully."
	fi
	if pgrep -f "freq_count_watchdog.sh" > /dev/null 2>&1 ; then
		LOGERR "FREQ_COUNT Watchdog could't be stopped."
	else
		LOGOK "FREQ_COUNT Watchdog stopped successfully."
	fi
	;;

	check)

	LOGSTART "FREQ_COUNT - CHECK Watchdog..."

	ERROR=0
	if [ -e "$LBPCONFIGDIR/daemon_stopped.cfg" ]; then
		LOGOK "FREQ_COUNT Daemon stopped manually. Will do nothing.."
	else
		if pgrep -f "freq_count_1" > /dev/null 2>&1 ; then
			LOGOK "FREQ_COUNT Daemon is running. Fine."
		else
			LOGERR "FREQ_COUNT Daemon is not running. That's not good."
			ERROR=1
		fi
		if pgrep -f "freq_count_watchdog.sh" > /dev/null 2>&1 ; then
			LOGOK "FREQ_COUNT Watchdog is running. Fine."
		else
			LOGERR "FREQ_COUNT Watchdog is not running. That's not good."
			ERROR=1
		fi
		if [ $ERROR -gt 0 ]; then
			cd $LBPBINDIR && $LBPBINDIR/freq_count_helper.sh start
		fi
	fi
	;;

*)
	echo "Usage: $0 [start|stop|check]" >&2
	exit 3
	;;

esac

LOGEND "Good Bye"

exit

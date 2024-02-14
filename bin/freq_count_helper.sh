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
	SAMPLERATE=$(jq -r '.samplerate' $LBPCONFIGDIR/plugin.json)
	REFRESHRATE=$(jq -r '.refreshrate' $LBPCONFIGDIR/plugin.json)
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
	pkill -f freq_count_watchdog.pl
	pkill -f freq_count_1
	sleep 1
	LOGINF "Command: $LBPBINDIR/freq_count_1 $GPIO -r$REFRESHRATE -s$SAMPLERATE -p700 -f $JSONFILE $VERBOSE >> $FILENAME"
	#$LBPBINDIR/freq_count_1 $GPIO -r$REFRESHRATE -s$SAMPLERATE -p700 -f $JSONFILE $VERBOSE >> $FILENAME &
	sleep 1
	if pgrep -f freq_count_1 > /dev/null 2>&1 ; then
		LOGOK "FREQ_COUNT Daemon started successfully."
	else
		LOGERR "FREQ_COUNT Daemon could't be started."
	fi
	LOGINF "Command: $LBPBINDIR/freq_count_watchdog.pl"
	#$LBPBINDIR/freq_count_watchdog.pl &
	sleep 1
	if pgrep -f freq_count_watchdog.pl > /dev/null 2>&1 ; then
		LOGOK "FREQ_COUNT Watchdog started successfully."
	else
		LOGERR "FREQ_COUNT Watchdog could't be started."
	fi
	;;

	stop)

	LOGSTART "FREQ_COUNT - STOP Daemon..."

	touch $LBPCONFIGDIR/daemon_stopped.cfg

	pkill -f freq_count_watchdog.pl
	pkill -f freq_count_1
	sleep 1
	if pgrep -f freq_count_1 > /dev/null 2>&1 ; then
		LOGERR "FREQ_COUNT Daemon could't be stopped."
	else
		LOGOK "FREQ_COUNT Daemon stopped successfully."
	fi
	if pgrep -f freq_count_watchdog.pl > /dev/null 2>&1 ; then
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
		if pgrep -f freq_count_1 > /dev/null 2>&1 ; then
			LOGOK "FREQ_COUNT Daemon is running. Fine."
		else
			LOGERR "FREQ_COUNT Daemon is not running. That's not good."
			ERROR=1
		fi
		if pgrep -f freq_count_watchdog.pl > /dev/null 2>&1 ; then
			LOGOK "FREQ_COUNT Watchdog iis running. Fine."
		else
			LOGERR "FREQ_COUNT Watchdog iis not running. That's not good."
			ERROR=1
		fi
		if [ $ERROR -gt 0 ]; then
			$LBPBINDIR/freq_count_helper.sh start
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

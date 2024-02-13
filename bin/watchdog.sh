#!/bin/bash

PLUGINNAME=REPLACELBPPLUGINDIR

# Create a new entry for the logfile (for logmanager)
. $LBHOMEDIR/libs/bashlib/loxberry_log.sh
PACKAGE=$PLUGINNAME
NAME=watchdog
LOGDIR=$LBPLOG/$PLUGINNAME
LOGSTART "WATCHDOG daemon started."
LOGOK "WATCHDOG daemon started."

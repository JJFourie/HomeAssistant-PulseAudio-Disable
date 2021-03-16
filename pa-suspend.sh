#!/bin/bash
###############################################################################
# Name:
#    pa-suspend    		(PulseAudio Suspend)
#
# Puspose:
#    Change the PulseAudio run command, to do error level logging instead of verbose logging. Then restart PulseAudio.
#    Load the PulseAudio "module-suspend-on-idle" module in the Home Assistant "hassio_audio" container.
#    This is done to prevent potential audio loss on the host device, and also reduce CPU usage in certain environments, 
#    caused by system-wide PulseAudio running in the hassio_audio container.
#    The module is loaded when
#    1. the script is started and the container is already running
#    2. the container is (re)started.
#
# Description: 
#    - When
#        a) the script starts, and the "hassio_audio" container is already running.
#        b) the "hassio_audio" container is (re)started.
#    - What
#        1) update the PulseAudio run parameters in /run/s6/services/pulseaudio/run
#           replace "-vvv" (verbose logging) with "--log-level=0" (log errors only).
#        2) Stop PulseAudio. It will automatically be restared using the new parameters. 
#        3) load the PulseAudio "module-suspend-on-idle" module inside "hassio_audio".
#    Continue to monitor Docker Events for "hassio_audio" container start events.
#    The script start- and module load events are reported to rsyslog as User events.
#
# Version 
#    v1.1  - Changed hassio_audio logging from verbose to error-only.
#    v1.2  - Fixed bug in Docker exec commands, expanded error checking.
#
###############################################################################
me=`basename "$0"`
RETVAL=0

event_filter="container=hassio_audio"
event_format="Container={{.Actor.Attributes.name}} Status={{.Status}}"

#------------------------------------------------------------------------------
# Function to change log level and load PulseAudio module
#------------------------------------------------------------------------------
function load_module () {
    # Change the PulseAudio run command: replace verbose logging with only logging errors. Then restart PulseAudio.
    res=$(docker exec -i hassio_audio sed -i 's/-vvv/--log-level=0/' /run/s6/services/pulseaudio/run 2>&1)
    if [[ "${?}" -ne "0" ]]; then
        logger -p user.err "${1}: Failed to change PA parameters in hassio_audio ($res)"
    fi
    # Restart PulseAudio.
    res=$(docker exec -i hassio_audio pkill pulseaudio 2>&1)
    if [[ "${?}" -ne "0" ]]; then
        logger -p user.err "${1}: Failed to kill PulseAudio in hassio_audio ($res)"
    fi

    # Load the PulseAudio suspend module
    res=$(docker exec -i hassio_audio pactl load-module module-suspend-on-idle 2>&1)
    if [[ "${?}" == "0" ]]; then
        logger -p user.notice  "${1}: PulseAudio module-suspend-on-idle loaded ok ($res)" 
    else
        logger -p user.err "${1}: PulseAudio module-suspend-on-idle failed to load! ($res)"
    fi
}

#------------------------------------------------------------------------------
# Function to wait forever and load module if hassio_audio is (re)started
#------------------------------------------------------------------------------
function event_loop () {
    while read line; do
      if [[ ${line} == *"Status=start" ]]; then
          # Container started. Wait to allow container to start (else may get "connection refused" error).
          sleep 5
          load_module "${me} (Container Start)"
      fi
  done
}

logger -p user.notice "${me}: Started"

# Check if hass_audio is already running, and addressable.
tmp=$(docker exec hassio_audio date 2>&1)
if [[ "${?}" == "0" ]]; then
    load_module "${me} (Script Start)"
else
  logger -p user.warning "${me}: Container hassio_audio not yet running "
fi

# Read the Container Events and pass to function loop to process.
docker events  --filter ${event_filter} --format "${event_format}" | event_loop

exit $RETVAL

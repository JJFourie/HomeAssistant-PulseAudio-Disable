#!/bin/bash

###############################################################################
# Name:
#    pa-suspend                 (PulseAudio Suspend)
#
# Puspose:
#    Change the PulseAudio run command, to replace verbose logging with error only logging. Then restart PulseAudio.
#    Load the PulseAudio "module-suspend-on-idle" module in the Home Assistant "hassio_audio" container.
#    This is done either when the script is started and the container is already running, or when the container is (re)started.
#    This is done to prevent audio issues and reduce CPU usage in certain environments, caused by system-wide PulseAudio running in the hassio_audio container.
#
# Description:
#    - When
#        a) the script starts, but the "hassio_audio" container is already running.
#        b) the script is already running, and then the "hassio_audio" container is (re)started.
#    - What
#        1) update the PulseAudio run parameters in /run/s6/services/pulseaudio/run
#           replace "-vvv" (verbose logging) with "--log-level=0" (log errors only).
#        2) Stop PulseAudio. It will automatically be restared using the new parameters.
#        3) load the PulseAudio "module-suspend-on-idle" module inside "hassio_audio".
#    Continue to monitor Docker Events for "hassio_audio" container start events.
#    The script start- and module load events are reported to rsyslog as User events.
#
# Execution
#    - Shell script:      ./pa-suspend.sh
#
# Version
#    v1.1  - Changed hassio_audio logging from verbose to error-only.
#    v1.2  - Fixed bug in Docker exec commands, expanded error checking.
#    v1.3  - Added boolean settings to enable/disable (1) change run params (2) load PA module
#
###############################################################################
me=`basename "$0"`
RETVAL=0

event_filter="container=hassio_audio"
event_format="Container={{.Actor.Attributes.name}} Status={{.Status}}"

DO_CHANGE_PARAMS=true
DO_LOAD_MODULE=true

#------------------------------------------------------------------------------
# Function to change parameters and load PulseAudio module
#------------------------------------------------------------------------------
function change_pulseaudio () {

    if [[ $DO_CHANGE_PARAMS = true ]]; then
        # Change the PulseAudio run command: replace verbose logging with only logging errors. Then restart PulseAudio.
        res=$(docker exec -i hassio_audio sed -i 's/-vvv/--log-level=0 --log-time=true/' /run/s6/legacy-services/pulseaudio/run 2>&1)
        if [[ "${?}" -ne "0" ]]; then
            logger -p user.err "${1}: Failed to change PA parameters in hassio_audio ($res)"
        fi
        # Restart PulseAudio.
        res=$(docker exec -i hassio_audio pkill pulseaudio 2>&1)
        if [[ "${?}" -ne "0" ]]; then
            logger -p user.err "${1}: Failed to kill PulseAudio in hassio_audio ($res)"
        fi
    fi

    if [[ $DO_LOAD_MODULE = true ]]; then
        # Load the PulseAudio suspend module
        res=$(docker exec -i hassio_audio pactl load-module module-suspend-on-idle 2>&1)

        if [[ "${?}" == "0" ]]; then
            logger -p user.notice  "${1}: PulseAudio module-suspend-on-idle loaded ok ($res)"
        else
            logger -p user.err "${1}: PulseAudio module-suspend-on-idle failed to load! ($res)"
        fi
    else
        logger -p user.notice "${1}: Not loading PulseAudio module-suspend-on-idle."
    fi

}

#------------------------------------------------------------------------------
# Function to wait forever and update container if hassio_audio is (re)started
#------------------------------------------------------------------------------
function event_loop () {
    while read line; do
      if [[ ${line} == *"Status=start" ]]; then
          # Container started. Wait to allow container to initialize (else may get "connection refused" error).
          sleep 5

          change_pulseaudio "${me} (Container Start)"

      fi
  done
}

logger -p user.notice "${me}: Started"

# Check if hass_audio is already running, and addressable.
tmp=$(docker exec hassio_audio date 2>&1)
if [[ "${?}" == "0" ]]; then
    change_pulseaudio "${me} (Script Start)"
else
  logger -p user.warning "${me}: Script started - container hassio_audio not running."
fi

# Read the Container Events and pass to function loop to process.
docker events  --filter ${event_filter} --format "${event_format}" | event_loop


exit $RETVAL


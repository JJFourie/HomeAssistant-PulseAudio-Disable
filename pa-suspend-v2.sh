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
#    A new version of the PulseAudio container "2022.04.1" (PA version 14.2) was released recently, with (amongst others) the following changes:
#    - the configuration file ("run") moved to a new location.
#    - PulseAudio does not run in verbose mode anymore. Based on the (volume of) container logs there is no need to change the log level.
#    The "suspend" module is not loaded by default though, and this is still required as the new version of the PulseAudio container otherwise still consumes high CPU.
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
#
# Execution
#    - Shell script:      ./pa-suspend.sh
#
# Version
#    v1.1  - Changed hassio_audio logging from verbose to error-only.
#    v1.2  - Fixed bug in Docker exec commands, expanded error checking.
#    v1.3  - Added boolean settings to enable/disable (1) change run params (2) load PA module
#    v2.0  - Changes to support new PulseAudio container version "2022.04.1"                                     (26-Nov-2022)
#            - First check if the legacy "run" config file still in original folder. if yes then update. 
#            - More dynamic check to wait until container is ready, before loading suspend module. 
#
###############################################################################
me=`basename "$0"`
RETVAL=0

DO_CHANGE_PARAMS=true
DO_LOAD_MODULE=true

pa_container="hassio_audio"
event_filter="container=hassio_audio"
event_format="Container={{.Actor.Attributes.name}} Status={{.Status}}"

legacy_config="/run/s6/services/pulseaudio/run"

#------------------------------------------------------------------------------
# Function to change parameters and load PulseAudio module
#------------------------------------------------------------------------------
function change_pulseaudio () {

    if [[ $DO_CHANGE_PARAMS = true ]]; then
        # Check if the legacy directory exists (still older version of container running).
        res=$( docker exec -i hassio_audio [[ -f \$legacyconfig ]] 2>&1 )
        if [[ "${?}" -eq "0" ]]; then
            # Change the PulseAudio run parameters: replace verbose logging with only logging errors. Then restart PulseAudio.
            res=$(docker exec -i hassio_audio sed -i 's/-vvv/--log-level=0 --log-time=true/' \$legacyconfig 2>&1)
            #res=$(docker exec -i hassio_audio bash -c "[[ -f \$legacyconfig ]] && sed -i 's/-vvv/--log-level=0 --log-time=true/' \$legacyconfig"  2>&1)
            if [[ "${?}" -eq "0" ]]; then
                # Restart PulseAudio (inside the container).
                res=$(docker exec -i hassio_audio pkill pulseaudio 2>&1)
                if [[ "${?}" -eq "0" ]]; then
                    sleep 1
                else
                    logger -p user.err "${1}: Failed to kill PulseAudio in hassio_audio ($res)"
                fi
            else
                logger -p user.err "${1}: Failed to change PA legacy parameters in hassio_audio ($res)"
            fi
        else
            logger -p user.err "${1}: PulseAudio legacy run parameters not found / updated."
        fi
    fi

    if [[ $DO_LOAD_MODULE = true ]]; then
        # Load the PulseAudio suspend module. Retry 10 times, with increasing delay to allow container to settle down.
        for i in {1..10};
        do
            res=$(docker exec -i hassio_audio pactl load-module module-suspend-on-idle 2>&1)
            if [[ "${?}" == "0" ]]; then
                logger -p user.err  "${1}: PulseAudio module-suspend-on-idle loaded ok ($i)($res)"
                break
            else
                sleep $i
            fi
        done
        if [[ "${?}" -ne "0" ]]; then
            logger -p user.err "${1}: PulseAudio module-suspend-on-idle failed to load! ($res)"
        fi
    else
        logger -p user.err "${1}: Not loading PulseAudio module-suspend-on-idle."
    fi
}

#------------------------------------------------------------------------------
# Function to listen forever and update container if hassio_audio is (re)started
#------------------------------------------------------------------------------
function event_loop () {
  while read line; do
      if [[ ${line} == *"Status=start" ]]; then
          # Container started.
          # Call function to set the run parameters, and load the suspend module.
          change_pulseaudio "${me} (Container Start)"
      fi
  done
}

#------------------------------------------------------------------------------
# Start of script
#------------------------------------------------------------------------------
logger -p user.err "${me}: Started"

# Check if hass_audio is already running, and it is already initialized.
tmp=$(docker exec hassio_audio date 2>&1)
if [[ "${?}" == "0" ]]; then
    logger -p user.notice "${1}:  $pa_container is already running when script was started. Loading module.."
    change_pulseaudio "${me} (Script Start)"
else
  logger -p user.warning "${me}: Script started - container hassio_audio not running."
fi

# Read the Container Events and pass to function loop to process.
docker events  --filter ${event_filter} --format "${event_format}" | event_loop

exit $RETVAL

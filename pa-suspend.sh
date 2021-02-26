#!/bin/bash
###############################################################################
# Name:
#    pa-suspend    		(PulseAudio Suspend)
#
# Puspose:
#    To prevent audio issues and reduce CPU usage in certain environments, caused by system-wide PulseAudio running in the hassio_audio container.
#
# Description: 
#    Monitor Docker events for container "hassio_audio".
#    When container is started, load the "module-suspend-on-idle" module inside the hassio_audio container.
#
# Execution 
#    - Docker cmd:    docker exec -i hassio_audio pactl load-module module-suspend-on-idle
#    - Shell script:  ./pa-suspend
#
###############################################################################
RETVAL=0

event_filter="container=hassio_audio"
event_format="Container={{.Actor.Attributes.name}} Status={{.Status}}"

function event_loop () {
  while read line; do

    #echo "$(date +%Y%m%d): ${line}"                                                                      #dbg

    if [[ ${line} == *"Status=start" ]]; then
        #echo "$(date +%Y%m%d): pa-suspend - hassio_audio started, loading suspend-on-idle module"        #dbg
        # Wait to allow container to start (else may get connection refused error).
        sleep 5
        docker exec -i hassio_audio pactl load-module module-suspend-on-idle
    fi
  done
}

docker events  --filter ${event_filter} --format "${event_format}" | event_loop


exit $RETVAL

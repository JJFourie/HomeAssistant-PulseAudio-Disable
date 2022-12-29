# HomeAssistant-PulseAudio-Disable    
    
At the time of writing there are issues caused by PulseAudio in the Home Assistant **```hassio_audio```** Docker container.    
- In some cases PulseAudio causes **loss of audio** for users who use audio on their host devices.    
- **PulseAudio consumes high CPU** on the host in some environments, e.g. when running Debian on a RPi, with a specific combination of OS version and ```hassio_audio``` release.    
    
One workaround for the high CPU usage is to load the [PulseAudio **```module-suspend-on-idle```**](https://www.freedesktop.org/wiki/Software/PulseAudio/Documentation/User/Modules/#module-suspend-on-idle) module in the ```hassio_audio``` container. As the name suggests, this module suspends the PulseAudio processing within ```hassio_audio``` when it is idle for some time.     
    
Below are a couple of ways to suspend PA:    
1) Manually from the command line using the Docker command set. This would be useful to test first if this solution actually helps your situation. This is not a long-term solution though, as the container is started again with the default configuration (how the container was created) after each restart/reboot, which means with the original parameters and without the suspend module.    
```docker exec -it hassio_audio pactl load-module module-suspend-on-idle```    
2) Execute the Docker command mentioned above, from within Home Assistant as a [HA Shell Command](https://www.home-assistant.io/integrations/shell_command/), either manually (button?) or perhaps as automation e.g. when HA starts up.    
3) Install the HA [OPHoperHPO hassio add-on](https://github.com/OPHoperHPO/hassio-addons/tree/master/pulseaudio_fix) that was created by Nikita Selin.    
4) Wrap the Docker command from (1) in a shell script that will load the module automatically whenever the hassio_audio container is (re)started.
        
   The solution discussed below is a crude way to implement this last option.    

    
**NOTE!**    
It seems that the new version "**2022.04.1**" of the ```hassio_audio``` PulseAudio container (released around April '22) has improved in that it stopped to spam the journal and downstream logging systems with verbose information messages. **"V2"** of this script will first confirm if the PulseAudio configuration file is still in the original location. If yes then it will set the runtime parameters as described below, and restart PulseAudio to allow the new configuration to be used. Else it means the newer version of the container is already implemented, and the script will then continue to only load the module to suspend PulseAudio.    
(See the ```journalctl``` command under "Useful Commands" to view the messages currently logged by your implementation).    
    
***This method assumes you are running Home Assistant in Docker in a "supervised" configuration***     
(It may also work for implementations running ```hassio```, but I don't have an environment to test and verify this)    
    
---
    
    
## Script     
    
### Functionality  
The script addresses two separate issues, namely:
   * Reduces CPU consumption of the ```hassio_audio``` container by suspending PulseAudio when idle.    
   * Reduces writing to logfiles by changing the PulseAudio log level from "verbose" to "error" (may not be an issue with latest version of the PA container).    
    
The PulseAudio ```pactl``` command that is used to load/unload PulseAudio modules is wrapped in a shell script. This script will be started on bootup, run in the background and automatically do its thing when needed, like when Home Assistant is restarted from within the UI, or when a new version of ```hassio_audio``` is released and the HA Supervisor (automatically) installs and reloads the container.     
  
    
[**pa-suspend-v2.sh**](https://github.com/JJFourie/HomeAssistant-PulseAudio-Disable/blob/main/pa-suspend-v2.sh) (V2!) is a simple shell script that will perform the below functionality when:     
   * the script (service) is started, and ```hassio_audio``` is already running.    
   * the script (service) is already running, and the ```hassio_audio``` container is (re)started.    
    
##### Actions  
The script will do the following (inside the PulseAudio container):
   1) Update the PulseAudio run parameters (```/run/s6/services/pulseaudio/run```) to change the logging from verbose (```"-vvv"```) to error (```"--log-level=0"```) logging.
   2) Add a parameter to display the system time in the logs (```"--log-time=true"```).
   3) Stop PulseAudio. PulseAudio will automatically be restarted, but now using the new parameters. So *it will no longer spam the logs with debug statements*.
   4) Load the PulseAudio ```module-suspend-on-idle``` module.
      - The script will then wait in an endless loop and listen to **Docker Events** related to the ```hassio_audio``` container.    
      - When a  ```hassio_audio``` container start event is received the script will repeat the actions listed above, i.e. set the run parameters, restart PulseAudio, and load the ```module-suspend-on-idle``` module inside the PulseAudio container.    
      - The script will raise events to rsyslog (facility = "user") when the script is started, and also when the module is (re)loaded.    
   (see /var/log/user.log)    
    
##### Configuration
The script uses two boolean variables that can be edited to change the program behavior. 
Both are initially true, which means the logging parameters are updated *and* the module is loaded to suspend PulseAudio when idle. 
Set the proper value based on your needs:    
Variable | | Description
--| -- | --
```DO_CHANGE_PARAMS``` |  | set to true to update the PulseAudio runtime parameters, false to skip.
```DO_LOAD_MODULE``` |  | set to true to load the PulseAudio ```module-suspend-on-idle``` module, false to skip.    
    
Note that if the ```docker exec``` command is executed immediately after receiving the container start event, the container is not accepting commands yet and a *"Connection failure: Connection refused"* error is raised. To prevent this error the script will try a couple of times (with an increased timeout between retries) to update the container, to allow the container to settle down. Based on your hardware and system performance you may have to increase this retry mechanism to make things work.     
    
    
## Implementation    
    
The shell script can be kicked off in a number of ways. Below are instructions to set it up as a Linux daemon service that will be automatically started on bootup.    
***Assumptions:***    
* Your script script will be called ```pa-suspend.sh```.    
* The script is located in ```/home/pi/Scripts```.    
* The service will run in the context of user ```pi```.    
    Set the proper "User=" setting for your environment in the [service file](https://github.com/JJFourie/HomeAssistant-PulseAudio-Disable/blob/main/pa-suspend.service).    
    This ensures that $HOME is set, to prevent the Docker error: ```"WARNING: Error loading config file: .dockercfg: $HOME is not defined"```    

***Instructions: (adjust to match your own implementation)***    
1) In the host OS (Debian?), create a shell script ```pa-suspend.sh``` by copying the contents from or downloading the [pa-suspend-v2.sh](https://github.com/JJFourie/HomeAssistant-PulseAudio-Disable/blob/main/pa-suspend-v2.sh) script.    
    ```sudo vi /home/pi/Scripts/pa-suspend.sh```    
2) Ensure the shell script is executable:     
    ```chmod +x /home/pi/Scripts/pa-suspend.sh```    
3) Create the service file, and enter the content from [pa-suspend.service](https://github.com/JJFourie/HomeAssistant-PulseAudio-Disable/blob/main/pa-suspend.service):     
    ```sudo vi /etc/systemd/system/pa-suspend.service```    
 4) Create the systemd service:    
    ```sudo systemctl enable pa-suspend```    
   This will also create any related symlinks.     
5) Check the status and confirm there are no errors.    
    ```sudo systemctl status pa-suspend```
    
    
---
    
---
    
    
## A. Useful Commands    
    
### Linux    
    
- **Service**:    
      - Start the ```pa-suspend``` service:    
        ```sudo systemctl start pa-suspend```    
      - Stop the service:    
        ```sudo systemctl stop pa-suspend```    
      - Disable the service. Also drops related sym links:    
        ```sudo systemctl disable pa-suspend```    
      - Reload the service, e.g. after editing or making changes:    
        ```sudo systemctl daemon-reload```    
      - Restart the service:    
        ```sudo systemctl restart pa-suspend```    
      - Edit an existing service. No need to reload the service afterwards:    
        ```sudo systemctl edit pa-suspend --full```    
	
- **Logging**:    
      - Use ```journalctl``` (-f shows logs in realtime continuously):    
        ```sudo journalctl -u pa-suspend [-f]```    
      - System logs:    
        ```tail [-f] /var/log/user.log```    
        
### Docker    
    
- List the Docker Images:    
    ```docker images```    
- List all running Docker containers:    
    ```docker ps```    
- Stop the specified container:    
    ```docker stop hassio_audio```    
- List the logs for the specified container (-f means continuous in realtime):    
    ```docker logs -f hassio_audio```    
- Execute a command inside a container:    
    ```docker exec -it <container> <command>```    
    
    
### PulseAudio    
    
- List (all) the PA modules currently loaded:    
    ```docker exec -it hassio_audio pactl list short modules```    
- List only the PA suspend module if it is currently loaded:    
    ```docker exec -it hassio_audio pactl list short modules | grep "suspend"```    

---
    
---
    
    
## B. Example Output    
    
Based on my implementation, below are some commands and their output, as reference to help you troubleshoot possible issues.    
    
1) Status of the implemented service:    
  **```sudo systemctl status pa-suspend```**    
```  
● pa-suspend.service - Loads PulseAudio suspend-on-idle module in hassio_audio when started
   Loaded: loaded (/etc/systemd/system/pa-suspend.service; enabled; vendor preset: enabled)
   Active: active (running) since Fri 2021-02-26 13:24:35 CET; 1h 22min ago
 Main PID: 1992 (pa-suspend.sh)
    Tasks: 11 (limit: 3858)
   CGroup: /system.slice/pa-suspend.service
           ├─1992 /bin/bash /home/pi/Scripts/pa-suspend.sh
           ├─1994 docker events --filter container=hassio_audio --format Container={{.Actor.Attributes.name}} Status={{.Status}}
           └─1995 /bin/bash /home/pi/Scripts/pa-suspend.sh
```
    
2) Check if the "pa-suspend" process is running:    
   (There should be two processes, as Bash forks on the "while read" command used in the script)     
  **```ps -ef | grep pa-suspend```**    
```
root      1992     1  0 13:24 ?        00:00:00 /bin/bash /home/pi/Scripts/pa-suspend.sh
root      1995  1992  0 13:24 ?        00:00:00 /bin/bash /home/pi/Scripts/pa-suspend.sh
```
    
3) Journal logs for a (successfully) running service:    
  **```sudo journalctl -u pa-suspend```**    
```
-- Logs begin at Fri 2021-02-26 13:24:24 CET, end at Fri 2021-02-26 14:25:14 CET. --
-- No entries --
```
    
4) Files and sym links created under "/etc" after successful setup:    
  **```sudo find /etc -name "*pa-suspend*" -print0 | xargs -0 ls -la```**    
```
lrwxrwxrwx 1 root root  38 Feb 26 12:54 /etc/systemd/system/multi-user.target.wants/pa-suspend.service -> /etc/systemd/system/pa-suspend.service
-rw-r--r-- 1 root root 253 Feb 26 12:44 /etc/systemd/system/pa-suspend.service
```
    
5) Successful manual load of the PulseAudio module:    
   The returned value is based on the number of modules currently loaded (but sometimes there are gaps)     
  **```docker exec -it hassio_audio pactl load-module module-suspend-on-idle```**    
```
16
```    
    
6) Failed manual load of module. In this case the module was already loaded, and it can't be loaded a second time:    
  **```docker exec -it hassio_audio pactl load-module module-suspend-on-idle```**    
```
Failure: Module initialization failed
```     

More detail on the error is logged by PulseAudio in ```/var/log/daemon.log```:    
```
Mar  5 01:08:27 RPiHost 8de681ad489c[676]: E: [pulseaudio] module.c: Module "module-suspend-on-idle" should be loaded once at most. Refusing to load.
Mar  5 01:08:27 RPiHost 8de681ad489c[676]: I: [pulseaudio] client.c: Freed 15 "pactl"
Mar  5 01:08:27 RPiHost 8de681ad489c[676]: I: [pulseaudio] protocol-native.c: Connection died.
```

7) Entries in system logs when the *```pa-suspend```* script is started.    
   On startup it will try to load the PulseAudio module, but in this case the module was already loaded, and an error was raised because it can't be loaded a second time:    
  **```tail -f /var/log/user.log```**    
```
Mar  5 01:11:38 RPiHost pi: pa-suspend.sh started
Mar  5 01:11:39 RPiHost pi: pa-suspend.sh (Script Start): PulseAudio module-suspend-on-idle failed to load! (Failure: Module initialization failed)
```
    
8) Docker "hassio_audio" logs at the time when the *```module-suspend-on-idle```* module is loaded:    
  **```docker logs -f hassio_audio```**    
```
...
I: [pulseaudio] module.c: Loaded "module-suspend-on-idle" (index: #16; argument: "").
I: [pulseaudio] client.c: Freed 0 "pactl"
I: [pulseaudio] protocol-native.c: Connection died.
I: [pulseaudio] module-suspend-on-idle.c: Sink auto_null idle for too long, suspending ...
D: [pulseaudio] sink.c: auto_null: suspend_cause: (none) -> IDLE
D: [pulseaudio] sink.c: auto_null: state: IDLE -> SUSPENDED
D: [pulseaudio] source.c: auto_null.monitor: suspend_cause: (none) -> IDLE
D: [pulseaudio] source.c: auto_null.monitor: state: IDLE -> SUSPENDED
D: [pulseaudio] core.c: Hmm, no streams around, trying to vacuum.
...
```
    
9) Listing of loaded PulseAudio modules (here the *```module-suspend-on-idle```* module is already loaded, see nr 16)    
  **```docker exec -it hassio_audio pactl list modules```**    
```
Module #0
	Name: module-device-restore
	Argument: 
	Usage counter: n/a
	Properties:
		module.author = "Lennart Poettering"
		module.description = "Automatically restore the volume/mute state of devices"
		module.version = "14.2"

Module #1
	Name: module-stream-restore
	Argument: 
	Usage counter: n/a
	Properties:
		module.author = "Lennart Poettering"
		module.description = "Automatically restore the volume/mute/device state of streams"
		module.version = "14.2"

Module #2
	Name: module-card-restore
	Argument: 
	Usage counter: n/a
	Properties:
		module.author = "Lennart Poettering"
		module.description = "Automatically restore profile of cards"
		module.version = "14.2"

Module #3
	Name: module-switch-on-port-available
	Argument: 
	Usage counter: n/a
	Properties:
		module.author = "David Henningsson"
		module.description = "Switches ports and profiles when devices are plugged/unplugged"
		module.version = "14.2"

Module #4
	Name: module-switch-on-connect
	Argument: 
	Usage counter: n/a
	Properties:
		module.author = "Michael Terry"
		module.description = "When a sink/source is added, switch to it or conditionally switch to it"
		module.version = "14.2"

Module #5
	Name: module-udev-detect
	Argument: tsched=0
	Usage counter: n/a
	Properties:
		module.author = "Lennart Poettering"
		module.description = "Detect available audio hardware and load matching drivers"
		module.version = "14.2"

Module #8
	Name: module-bluetooth-discover
	Argument: 
	Usage counter: n/a
	Properties:
		module.author = "João Paulo Rechi Vita"
		module.description = "Detect available Bluetooth daemon and load the corresponding discovery module"
		module.version = "14.2"

Module #9
	Name: module-bluez5-discover
	Argument: 
	Usage counter: n/a
	Properties:
		module.author = "João Paulo Rechi Vita"
		module.description = "Detect available BlueZ 5 Bluetooth audio devices and load BlueZ 5 Bluetooth audio drivers"
		module.version = "14.2"

Module #10
	Name: module-native-protocol-unix
	Argument: auth-anonymous=1 auth-cookie-enabled=0 socket=/data/external/pulse.sock
	Usage counter: n/a
	Properties:
		module.author = "Lennart Poettering"
		module.description = "Native protocol (UNIX sockets)"
		module.version = "14.2"

Module #11
	Name: module-default-device-restore
	Argument: 
	Usage counter: n/a
	Properties:
		module.author = "Lennart Poettering"
		module.description = "Automatically restore the default sink and source"
		module.version = "14.2"

Module #13
	Name: module-always-sink
	Argument: 
	Usage counter: n/a
	Properties:
		module.author = "Colin Guthrie"
		module.description = "Always keeps at least one sink loaded even if it's a null one"
		module.version = "14.2"

Module #14
	Name: module-null-sink
	Argument: sink_name=auto_null sink_properties='device.description="Dummy Output"'
	Usage counter: 0
	Properties:
		module.author = "Lennart Poettering"
		module.description = "Clocked NULL sink"
		module.version = "14.2"

Module #15
	Name: module-position-event-sounds
	Argument: 
	Usage counter: n/a
	Properties:
		module.author = "Lennart Poettering"
		module.description = "Position event sounds between L and R depending on the position on screen of the widget triggering them."
		module.version = "14.2"

Module #16
	Name: module-suspend-on-idle
	Argument: 
	Usage counter: n/a
	Properties:
		module.author = "Lennart Poettering"
		module.description = "When a sink/source is idle for too long, suspend it"
		module.version = "14.2"
```



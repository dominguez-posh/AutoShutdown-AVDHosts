# AutoShutdown-AVDHosts

The Script will to several Things:

- Disconnecting Usersessions, wich are idling on a host. (Time is adjustable)
- Logging off Usersessions, that are disconnected (Time is adjustable)
- Shutting down a Session-Host with no usersessions active.

For shutdown, the script took first the sessionhost in drainmode, waits 10 seconds, shuts down the host and disabled the drainmode.
This is set to avoid that no user is connecting while the shutdown process.

## The Script Auto Shutdown the AVD Clients in a Azure function.

To Run, you need to create a normal Powershell Azure function.

Important: The Azure function needs to be Systemassigned and needs Contributor Rights to The Ressources:
![image](https://github.com/dominguez-posh/AutoShutdown-AVDHosts/assets/9081611/e959d948-cabd-40cb-a276-3d96791b22de)

![image](https://github.com/dominguez-posh/AutoShutdown-AVDHosts/assets/9081611/ee7e962a-5246-4734-8904-a365044956ef)

How often the autommation wil run, you can adjust with a Time-Trigger.
Using the default is good to go (Script runs every 5 Minutes) but you can adjust that of cause.

![image](https://github.com/dominguez-posh/AutoShutdown-AVDHosts/assets/9081611/ad38d69a-711c-4882-95e8-b751f73152d1)

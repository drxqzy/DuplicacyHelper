# DuplicacyHelper
Script to automate duplicacy backups on macOS. 

## Introduction 
A shell script to automate duplicacy backups on macOS in combination with launchd.
This Readme references [Duplicacy nomenclature](https://forum.duplicacy.com/t/about-duplicacy-nomenclature/).

What DuplicacyHelper does:
* Schedules Duplicacy backups and pruning at a set interval.
* Checks battery state to ensure that Duplicacy does not run in background when battery is low, unless plugged into AC power.
* Checks current wireless network SSID to ensure that Duplicacy only runs when connected to a whitelisted SSID.
* Uses `launchd` to run silently in the background (set once and forget).
* Integrates with HealthChecks.io and macOS notifications for feedback.

What DuplicacyHelper does not do:
* Initiates (`duplicacy init`) a repository - use Duplicacy to `init` a new repository first before setting up DuplicacyHelper.
* Checks Wi-Fi network against a BSSID (MAC address) whitelist. This was the original intention but there seems to be no simple way to do this in recent iterations of macOS where BSSID is redacted from shell.
* Reinvent filters for Duplicacy. Use Duplicacy's native `filters` file.

<i>The original script was written and tested on a Macbook Air running macOS 15.2</i>.

## Setup
> [!IMPORTANT]
> Ensure that the repository has already been initiated in Duplicacy, by `duplicacy init`. DuplicacyHelper only works with an existing repository.

Copy the following two files into `/.duplicacy/` of the current repository. While it is suggested to place them in `/.duplicacy/` for convenience, they may technically reside anywhere as long as both files are in the same folder.

[`duplicacyhelper.sh`](duplicacyhelper.sh)   
[`com.qz.duplicacyhelper.plist`](com.qz.duplicacyhelper.plist)

Several settings in `com.qz.duplicacyhelper.plist` need to be configured.
Keys in `com.qz.duplicacyhelper.plist` that need configuration are prefixed with `set...`.

## Configuring Duplicacy Helper Options

### Backup Interval
```
<key>setBackupIntervalDays</key>
<integer>7</integer>
```
The desired interval between Duplicacy backups, in days. Set to `7` by default. Differences in time zone are not accounted for.  

DuplicacyHelper checks the current time against the timestamp of the latest revision to determine if backup is due. This is the first step in the script and always runs, regardless of battery status or wireless network SSID. The timestamp is stored locally in `com.qz.duplicacyhelper.plist` after each successful backup run, so network connectivity is not required for this step.

If set to `0`, DuplicacyHelper will always attempt a backup as frequently as it is triggered by `launchd`, subject to battery and network checks below.

### Battery Check
```
<key>setBattThreshold</key>
<integer>40</integer>
```
The minimum battery charge required to proceed with backups, in percentage (%). Set to `40` by default.

If backup is due, DuplicacyHelper checks if Macbook battery charge is at least this level before proceeding. DuplicacyHelper will always proceed if Macbook is plugged into an AC source, regardless of battery charge. This check is only performed once at the start, and DuplicacyHelper will not abort if the battery or power state changes subsequently.

If set to `0`, DuplicacyHelper ignores battery and power state check.

### Network Check
```
<key>ssidWhitelist</key>
<array>
	<string>InsertSSIDHere</string>
</array>
```
A whitelist of wireless networks which DuplicacyHelper will run backups on. Contains one placeholder entry, `InsertSSIDHere`, by default.

If backup is due and battery check is passed, DuplicacyHelper checks if the current wireless network's SSID matches one on the whitelist. If the current network's SSID is not on the whitelist, DuplicacyHelper will not proceed.

> [!IMPORTANT]
> The whitelist must contain at least one entry for DuplicacyHelper to work properly.

### Options for `duplicacy backup`
```
<key>setBackupOpt</key>
<string>-threads 20</string>
```
This string contains options to pass to `duplicacy backup`, which runs if all the above checks are passed. As an example, set to `-threads 20` by default. If left blank, `duplicacy backup` will run without any additional options.

### Options for `duplicacy prune`

```
<key>setPruneOpt</key>
<string>-a -keep 30:180 -keep 7:30</string>
```
This string contains options to pass to `duplicacy prune`, which runs after `duplicacy backup`. As an example, set to `-a -keep 30:180 -keep 7:30` by default. If left blank, `duplicacy prune` will run without any additional options.

### _Healthchecks.io_ Integration

```
<key>setHealthchecksURL</key>
<string>https://hc-ping.com/uuid</string>
```
Ping URL for integration with _Healthchecks.io_. Set to a placeholder, `https://hc-ping.com/uuid`, by default. URL must be in *uuid format* and not slug/ping key. URL must not contain a trailing `/`.

This setting is optional, and if left blank, DuplicacyHelper will function normally while skipping pings to _Healthchecks.io_.

## Configuring LaunchAgent

Copy this plist into `~/Library/LaunchAgents/`.

[`com.qz.duplicacyhelper.launchagent.plist`](com.qz.duplicacyhelper.launchagent.plist)

### Point to DuplicacyHelper
```
<key>ProgramArguments</key>
<array>
	<string>/.duplicacy/duplicacyhelper.sh</string>
</array>
```
Edit this string to point to the path of `duplicacyhelper.sh`. Note that the absolute path should be used, as `launchd` will not resolve `~` or `$HOME`.

### Configure StartInterval
```
<key>StartInterval</key>
<integer>86400</integer>
```
This determines how frequently `launchd` runs DuplicacyHelper, in seconds. Note that this frequency determines how often DuplicacyHelper runs to perform the checks above (Backup Interval, Battery, Network etc), and not the desired interval of Duplicacy backups.

It is not recommended to set `StartInterval` longer than the desired backup interval, unless you intend to run additional backups manually or by other processes.

### Configure ThrottleInterval
```
<key>ThrottleInterval</key>
<integer>3600</integer>
```
This determines the frequency that DuplicacyHelper retries unsuccessful backup attempts, *if backups are due (based on `setBackupIntervalDays`)*, but the process was unsuccessful (eg., failed Battery or Network checks, or `duplicacy` process crashed).

Set to `3600` (1 hour) by default.

## Starting DuplicacyHelper
Having configured DuplicacyHelper options and the LaunchAgent options, DuplicacyHelper is ready to load and start. Run the following in Terminal:

`launchctl bootstrap gui/$UID ~/Library/LaunchAgents/`

This can also be done with any launchd manager of choice (eg. LaunchControl). To confirm that DuplicacyHelper has been loaded successfully, run `launchctl print gui/$UID/com.qz.duplicacyhelper`.

On first run, DuplicacyHelper will always attempt a backup as the default `lastRvTime` is 0.  
<sub>(Unless your backup interval is 55 years. Do you _really_ need DuplicacyHelper?)</sub>

## Success and Error Codes

If DuplicacyHelper determines that backup is not yet due, it exits silently with no error, without pinging _Healthchecks.io_, and without a macOS notification.

If DuplicacyHelper determines that backup is due, but fails, it exits with the following error codes:

|*Exit Code*|*Description*|
|-----------|---|
|`12`       |Battery below set threshold, and not connected to AC power.| 
|`13`       |Not connected to a network with an SSID on the whitelist.  |
|Others     |Likely related to `duplicacy`. If any `duplicacy` process exits with a non-zero error code, DuplicacyHelper also exits with the corresponding error code. Refer to Duplicacy documentation.|

DuplicacyHelper logs stdout and stderr to `duplicacyhelper.log`.

#### Footnotes
This script was originally written to automate personal backups on my device, mostly for convenience, and partially for fun.
I'm not a tech professional or in any related line, so had to ~~struggle~~ learn a lot while writing this. I apologise for the amateurish code but it is my hope that putting it here may help other like-minded individuals.

This script was inspired by `duplicacy-util`, created by jeffaco. <sup>o7</sup>  
My heartfelt appreciation to gilbertchen for developing Duplicacy.

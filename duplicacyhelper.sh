#!/bin/zsh
PATH=/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/System/Cryptexes/App/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin:/var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/local/bin:/var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/bin:/var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/appleinternal/bin
exec >duplicacyhelper.log 2>&1
setopt pipefail print_exit_value

# to reference source script directory use "${0:A:h}"
#plist="${0:A:h}/com.qz.duplicacyhelper.plist"
plist="./com.qz.duplicacyhelper.plist"
# check time interval from latest revision timestamp vs current
last=$(plutil -extract lastRvTime raw "$plist")
now=$(date -j +%s)

# adjust n days x 86400 = seconds
if [[ $now-$last -lt $(($(plutil -extract setBackupIntervalDays raw "$plist")*86400)) ]]; then
	exit
fi

# code for healthchecks.io
# curl <url> to ping check for success (exit 0)
# curl <url>/x to ping check for failure with exit code x
_pinghc() {
	_pingurl=$(plutil -extract setHealthchecksURL raw "$plist")
	if [[ $_pingurl != '' ]]; then
		curl -s --retry 1 $_pingurl/$1 > /dev/null 2>&1
	fi
}
# usage: _pinghc xx to ping healthchecks with error code xx. Important: _pinghc 0 for success!

# code for power source checks:
# pmset -g ps | sed -En "s/.*\'(.*) Power\'$/\1/p"
# returns AC or Battery
# pmset -g ps | sed -En 's/.*[^0-9]([0-9]+)%;.*/\1/p'
# returns an integer which is %age of battery

# check battery
if [[ $(pmset -g ps | sed \-En 's/.*[^0-9]([0-9]+)%;.*/\1/p') -lt $(plutil -extract setBattThreshold raw "$plist") ]] \
&& [[ $(pmset -g ps | sed -En "s/.*\'(.*) Power\'$/\1/p") == 'Battery' ]]; then
# if battery low, check if power is on Battery
	osascript -e 'display notification "Duplicacy backup due! Battery low." with title "Duplicacy Helper"'
	_pinghc 12; exit 12
fi

# get current SSID
ssid=$(ipconfig getsummary $(networksetup -listallhardwareports | awk '/Hardware Port: Wi-Fi/{getline; print $2}') | awk -F ' SSID : ' '/ SSID : / {print $2}')
#check SSID
ssidcount=$(plutil -extract ssidWhitelist raw "$plist")
for i in {1..$ssidcount}; do
    if [[ $ssid == $(plutil -extract ssidWhitelist.$(($i-1)) raw "$plist") ]]; then
		#if SSID match whitelist stop further loops
		break
	elif [[ $i == $(($ssidcount)) ]]; then
		# if no match and on last loop, exit with error code 13 (no network)
		osascript -e 'display notification "Duplicacy backup due! Connect to whitelisted wireless network." with title "Duplicacy Helper"'
	_pinghc 13; exit 13
	fi
done

### END OF CHECKS ###
### START OF MAIN BACKUP SCRIPT ###

osascript -e 'display notification "Duplicacy backup starting." with title "Duplicacy Helper"'

drepopath=$(plutil -extract setRepoPath raw "$plist")
dbackupopt=$(plutil -extract setBackupOpt raw "$plist")
dpruneopt=$(plutil -extract setPruneOpt raw "$plist")

# Run all duplicacy commands with -comment DuplicacyHelper
cd $drepopath;duplicacy -comment DuplicacyHelper backup ${=dbackupopt}
# The following block of code captures the exit code of the duplicacy process and allows DuplicacyHelper to exit with failure code if duplicacy was unsuccessful. Repeat after all duplicacy commands. 
exitcode=$?; if [[ $exitcode != 0 ]]; then
	osascript -e 'display notification "Duplicacy failed. Try again or check logs." with title "Duplicacy Helper"'
	_pinghc $exitcode; exit $exitcode
fi

cd $drepopath;duplicacy -comment DuplicacyHelper prune ${=dpruneopt}
exitcode=$?; if [[ $exitcode != 0 ]]; then
	osascript -e 'display notification "Duplicacy failed. Try again or check logs." with title "Duplicacy Helper"'
	_pinghc $exitcode; exit $exitcode
fi

# Update lastRvTime
duplicacy -comment DuplicacyHelper list | sed -En 's/.*created at (.*)([0-9][0-9]:[0-9][0-9]).*/date -j -f "%F %T" "\1\2:00" "+%s"/p' | tail -n 1 | sh | xargs -I{} plutil -replace lastRvTime -integer {} "$plist"
exitcode=$?; if [[ $exitcode != 0 ]]; then
	osascript -e 'display notification "Duplicacy failed. Try again or check logs." with title "Duplicacy Helper"'
	_pinghc $exitcode; exit $exitcode
fi

osascript -e 'display notification "Duplicacy backup completed." with title "Duplicacy Helper"'

_pinghc 0; exit

### END OF MAIN SCRIPTS ###

## Footnotes ##
#Exit codes
#0: Success
#11: Not due (time interval below threshold) - DEPRECIATED. Need to exit 0 for launchd keepalive
#12: Battery status (lower than threshold and not plugged into charger)
#13: Network status (not on whitelisted networks)
#Other exit codes: Duplicacy crash. Check against Duplicacy exit codes. 
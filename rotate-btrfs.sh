#!/bin/bash

#default config location
config_file="/etc/rsnapshot.conf"

declare -a commands=()

#parse arguments
while [ "$1" != "" ]
do
	case $1 in
		-c )	shift
			config_file=$1
			;;

		* )	commands+=($1)
			;;
	esac

	shift
done

if [ "${#commands[@]}" -gt 1 ]
then
	echo "multiple command entered, enter only one command"
fi

if ! [ -f $config_file ]
then
	echo "config file not found"
	exit 1
fi

declare -a backups_level=()
declare -a backups_level_count=()

#read config file
while read -r line
do
	first_char=${line:0:1}
	#skip if first char is comment or empty line
	if [[ $first_char != "#" ]] && [[ -n $first_char ]]
	then

		declare -a elements=()
		#break line into elements
		for word in $line
		do
			elements+=($word)
		done

		#save variables
		if [[ ${elements[0]} == "snapshot_root" ]]
		then
			snapshot_root="${elements[1]}"
		fi

		if [[ ${elements[0]} == "retain" ]] 
		then
			backups_level+=(${elements[1]})	
			backups_level_count+=(${elements[2]})	
		fi

		if [[ ${elements[0]} == "logfile" ]] 
		then
			logfile="${elements[1]}"
		fi

		if [[ ${elements[0]} == "lockfile" ]] 
		then
			lockfile="${elements[1]}"
		fi

		if [[ ${elements[0]} == "sync_first" ]]
		then
			sync_first="${elements[1]}"
		fi

	fi
done < $config_file

#check pid file
if [ -f $lockfile ]
then
	pgrep -F $lockfile
	if [ $? -eq 1 ]
	then
		rm $lockfile
	else 
		echo "rsnapshot instance is already running" >> $logfile
		exit
	fi
fi

echo $$ > $lockfile

#check sync first 
if [[ $sync_first != "1" ]]
then
	echo "sync not turn on" >> $logfile
fi

#check if command specified is found in config file and save its index
declare -i command_found=0

for i in "${!backups_level[@]}"
do
	if [[ $commands == ${backups_level[$i]} ]]
	then
		command_found=1
		command_index=$i
		break
	fi
done

if [ $command_found -ne 1 ]
then
	echo "command not found" >> $logfile
	exit 1
fi

echo "$commands: started" >> $logfile

#delete oldest snapshot if it exist
if [ -d "$snapshot_root/${backups_level[$command_index]}.$((${backups_level_count[$command_index]}-1))" ]
then
	echo "btrfs subvolume delete $snapshot_root/${backups_level[$command_index]}.$((${backups_level_count[$command_index]}-1))" >> $logfile
	btrfs subvolume delete "$snapshot_root/${backups_level[$command_index]}.$((${backups_level_count[$command_index]}-1))" >> $logfile
	btrfs_return_value=$?
	if [ $btrfs_return_value -ne 0 ]
	then
		echo "Error: Failed to delete snapshot $snapshot_root/${backups_level[$command_index]}.$((${backups_level_count[$command_index]}-1)). Error code: $btrfs_return_value" >> $logfile
		exit 1
	fi
fi

#rotate backups
for ((j=${backups_level_count[$command_index]}-1 ; j>=1; j--))
do
	if [ -d $snapshot_root/${backups_level[$command_index]}.$(($j-1)) ]
	then
		echo "mv $snapshot_root/${backups_level[$command_index]}.$(($j-1)) $snapshot_root/${backups_level[$command_index]}.$j" >> $logfile
		mv $snapshot_root/${backups_level[$command_index]}.$(($j-1)) $snapshot_root/${backups_level[$command_index]}.$j >> $logfile
		if [ -d $snapshot_root/${backups_level[$command_index]}.$(($j-1)) ]
		then
			echo "Error: failed to move $snapshot_root/${backups_level[$command_index]}.$(($j-1))" >> $logfile
			exit 1
		fi
	fi
done

#move backup levels 
if [ $command_index -eq 0 ]
then
	if [ -d $snapshot_root/.sync ]
	then
		echo "btrfs subvolume snapshot $snapshot_root/.sync $snapshot_root/${backups_level[$command_index]}.0" >> $logfile
		btrfs subvolume snapshot $snapshot_root/.sync $snapshot_root/${backups_level[$command_index]}.0 >> $logfile
		btrfs_return_value=$?
		if [ $btrfs_return_value -ne 0 ]
		then
			echo "Error: Failed to create snapshot $snapshot_root/${backups_level[$command_index]}.0 Error code: $btrfs_return_value" >> $logfile
			exit 1
		fi
	else
		echo ".sync doesn't exist" >> $logfile
	fi
else
	if [ -d $snapshot_root/${backups_level[$(($command_index-1))]}.$((${backups_level_count[$(($command_index-1))]}-1)) ]
	then
		echo "mv $snapshot_root/${backups_level[$(($command_index-1))]}.$((${backups_level_count[$(($command_index-1))]}-1)) $snapshot_root/${backups_level[$command_index]}.0" >> $logfile
		mv $snapshot_root/${backups_level[$(($command_index-1))]}.$((${backups_level_count[$(($command_index-1))]}-1)) $snapshot_root/${backups_level[$command_index]}.0 > $logfile
		if [ -d $snapshot_root/${backups_level[$(($command_index-1))]}.$((${backups_level_count[$(($command_index-1))]}-1)) ] 
		then
			echo "Error: failed to move $snapshot_root/${backups_level[$(($command_index-1))]}.${backups_level_count[$(($command_index-1))]}" >> $logfile 
			exit 1
		fi
	else
		echo "$snapshot_root/${backups_level[$(($command_index-1))]}.${backups_level_count[$(($command_index-1))]} doesn't exist yet" >> $logfile
	fi
fi

if [ -f $lockfile ]
then
	rm $lockfile
fi

echo "$commands: completed successfully" >> $logfile


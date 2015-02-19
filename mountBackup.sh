#!/bin/bash
function display_usage() {
    echo
    echo "This script will open up to two partition(s) of a disk as LUKS devices,"
    echo "mount them, wait for the backup to commence and eject the disk safely." 
    echo ""
    echo "Usage:"
    echo "$0 device keyfile"
    echo "    device: identifier of the hard disk (e.g. sde)."
    echo "            The first and second partition will be used, if they are LUKS devices"
    echo "    keyfile: the keyfile used to unlock the LUKS containers" 
} 

function is_luks_partition(){
    local partition=$1   
	
	if [ ! -b "$partition" ] 
	then
	    echo "INFO: $partition is not a block device."
	    return 1
	fi
	
    sudo cryptsetup isLuks $partition
	if [ $? -ne 0 ]
	then 
	    echo "INFO: $partition is not an encrypted partition."
	    return 1
	fi
	
    echo "OK: $partition is an encrypted partition and will be unlocked."
    return 0
}

function is_keyfile(){
    if [ -f "$1" ]
	then
	    echo "OK: $1 is a file and will be used as the keyfile."
	    return 0
	fi
	return 1
}

function open_luks_partition(){
    local partition=$1
    local name=$2
    local keyfile=$3
    sudo cryptsetup luksOpen $partition $name -d $keyfile
	if [ $? -ne 0 ]
	then 
	    echo "ERROR: Could not open the encrypted partition $partition with keyfile $keyfile"
	    exit 3
	fi
	echo "INFO: Successfully opened $partition mapped to $name"
}

function close_luks_volume(){
    local name=$1
	sudo cryptsetup luksClose $name
	if [ $? -ne 0 ]
	then 
	    echo "ERROR: Could not close the encrypted partition mapped to $name" 
	    return 1
	fi
}

function close_all_opened_luks_partitions(){
    close_luks_volume backup
	local errors_on_close=$?
	if [ "$is_raid_configuration" = true ]
	then
	    close_luks_volume backup-vol2
	    errors_on_close=$(( $errors_on_close + $? )) 
	fi
	
	if [ "$errors_on_close" -gt 0 ]
	then
	    echo ERROR: Not all LUKS partitions could be closed!
	    exit 10
	fi
}

function copy_logfile_with_confirmation(){
    echo ==============================================================================
	read -p "Do you want to copy the log file '$LOGFILE' to the mounted drive? " -n 1 -r
	echo
	if [[ $REPLY =~ ^[Yy]$ ]]
	then
	    if [ -f "$LOGFILE" ]
	    then
			currentTimestamp=$(date +%Y%m%d_%H%M)
		    cp $LOGFILE /mnt/backup/obnam-$currentTimestamp.log
	    else
	        echo "WARNING: $LOGFILE is NOT a file and was skipped."
	        return 1
	    fi
	fi
}

function show_and_link_obnam_config (){
    echo ==============================================================================
	echo content of the current ~/.obnam.conf:
	ls -la ~/.obnam.conf
	cat ~/.obnam.conf
	echo ==============================================================================
#	read -p "Do you want to link to the .obnam conf on the mounted drive? " -n 1 -r
#	echo        # (optional) move to a new line
#	if [[ $REPLY =~ ^[Yy]$ ]]
#	then
#	    ln -sf /mnt/backup/.obnam.conf .obnam.conf
#	    echo content of the current ~/.obnam.conf:
#	    cat ~/.obnam.conf
#	fi
}

function mount_backup(){
    sudo btrfs device scan
    sudo mkdir -p /mnt/backup
	sudo mount /dev/mapper/backup /mnt/backup/
	echo
	sudo btrfs fi show /dev/mapper/backup
	echo
	sudo btrfs fi df /mnt/backup/
	echo 
}

function unmount_backup(){
	while [ -d /mnt/backup ]
	do
	    sudo umount /mnt/backup
	    sudo rm -d /mnt/backup
	    if [ -d /mnt/backup ]
	    then
            echo Retrying to unmount and remove /mnt/backup...
	        sleep 5
	    fi
	done
}


backup_device=/dev/${1}
backup_partition_one=${backup_device}1
backup_partition_two=${backup_device}2
keyfile=$2
LOGFILE=~/obnam.log


if ( ! is_luks_partition $backup_partition_one )
then
    echo "ERROR: the first partition is not a LUKS device."
    display_usage
    exit 1
fi

if ( ! is_luks_partition $backup_partition_two )
then
    is_raid_configuration=false
    echo "INFO: Will open an mount ONE single partition."
else
    is_raid_configuration=true
    echo "INFO: Will open TWO partitions and mount the first (assuming a Btrfs RAID)."
fi


if ( ! is_keyfile "$keyfile" )
then
    echo "ERROR: $keyfile is not a file."
    display_usage
    exit 2
fi

read -p "Press [Enter] key to unlock and mount..."

open_luks_partition $backup_partition_one backup $keyfile
if [ "$is_raid_configuration" = true ]
then
    open_luks_partition $backup_partition_two backup-vol2 $keyfile
fi

mount_backup

show_and_link_obnam_config

echo
echo ==============================================================================
echo mounting complete, start the backup in a different terminal
echo ==============================================================================
echo
read -p "Press [Enter] key to umount and luksClose..."
read -p "Has the Backup really finished? [Enter]"

copy_logfile_with_confirmation

unmount_backup

close_all_opened_luks_partitions

echo "INFO: Unmounted and closed the partition(s). It is safe to unplug the disk now."
exit 0
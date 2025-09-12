#!/bin/bash

while [ "$1" != "" ]
do
	if ! [ -d temp ]
	then
		mkdir temp
	fi

	mv $1/* temp/
	rmdir $1
	btrfs subvolume create $1
	mv temp/* $1/

	rmdir temp
	
	shift
done


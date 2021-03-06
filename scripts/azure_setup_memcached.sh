#!/usr/bin/env bash

#TODO take as argument the ip of machine where I want to set up memcached
username=$1
machine_address=$2
port=$3

if [ -z $username ] || [ -z $machine_address ] || [ -z $port ]
then
echo "Use arguments: username machine_address port"
exit 1
fi

ssh $username@$machine_address "
    export DEBIAN_FRONTEND=noninteractive
    echo '--- Updating ---'
    sudo apt-get --assume-yes update
    echo '--- Installing required libraries ---'
    sudo apt-get --assume-yes install build-essential libevent-dev memcached
    echo '--- Starting memcached ---'
    memcached -p $port -t 1
"



# sh scripts/azure_setup_memcached.sh pungast pungastforaslvms3.westeurope.cloudapp.azure.com 11211
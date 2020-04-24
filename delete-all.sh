#!/bin/bash

#This script removes the resource groups (You will need to make the PREFIX match the one used to create the resources)

PREFIX=mfdns
RG_HUB=$(echo $PREFIX)-hub
RG_SPOKE=$(echo $PREFIX)-spoke

az group delete -n $RG_HUB --yes --no-wait
az group delete -n $RG_SPOKE --yes --no-wait
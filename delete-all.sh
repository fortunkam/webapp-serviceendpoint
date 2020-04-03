#!/bin/bash

#This script removes the resource groups (You will need to make the PREFIX match the one used to create the resources)

PREFIX=mfdns07
RG_HUB=$(echo $PREFIX)-hub
RG_SPOKE=$(echo $PREFIX)-spoke
RG_DEPLOY=$(echo $PREFIX)-deploy

az group delete -n $RG_DEPLOY --yes --no-wait
az group delete -n $RG_HUB --yes --no-wait
az group delete -n $RG_SPOKE --yes --no-wait
#!/bin/bash

################################################################################
# All the required static variables are declared here, most are derived from 
# a common PREFIX 
################################################################################
STARTDATE=$(date +"%H:%M:%S")

PREFIX=mfdns
RG_HUB=$(echo $PREFIX)-hub
RG_SPOKE=$(echo $PREFIX)-spoke
RG_DEPLOY=$(echo $PREFIX)-deploy
LOC=centralus
SUBID=$(az account list --query "[?isDefault].id" -o tsv)

VNET_HUB=$(echo $PREFIX)-hub-vnet
VNET_SPOKE=$(echo $PREFIX)-spoke-vnet

VNET_HUB_IPRANGE=10.0.0.0/16
VNET_SPOKE_IPRANGE=10.1.0.0/16

FIREWALL_SUBNET=AzureFirewallSubnet
VM_SUBNET=vm
FIREWALL_SUBNET_IPRANGE=10.0.0.0/24
VM_SUBNET_IPRANGE=10.0.1.0/24

APPGATEWAY_SUBNET=appgateway
WEB_SUBNET=web
DATA_SUBNET=data
APPGATEWAY_SUBNET_IPRANGE=10.1.0.0/24
WEB_SUBNET_IPRANGE=10.1.1.0/24
DATA_SUBNET_IPRANGE=10.1.2.0/24

HUB_TO_SPOKE_VNET_PEER=$(echo $PREFIX)-hub-spoke-peer
SPOKE_TO_HUB_VNET_PEER=$(echo $PREFIX)-spoke-hub-peer

STORAGE=$(echo $PREFIX)astore
STORAGE_CONNECTION_NAME=$(echo $PREFIX)-private-link
STORAGE_PRIVATE_ENDPOINT=$(echo $PREFIX)-storage-private-endpoint
STORAGE_DNS_LINK_SPOKE=$(echo $PREFIX)-storage-dns-spoke-link
STORAGE_DNS_LINK_HUB=$(echo $PREFIX)-storage-dns-hub-link
TABLE_DNS_ZONE=privatelink.table.core.windows.net
TABLE_NAME=Demo

APPPLAN=$(echo $PREFIX)-appplan
WEBSITE=$(echo $PREFIX)-site

FWPUBLICIP_NAME=$(echo $PREFIX)-fw-ip
FWNAME=$(echo $PREFIX)-fw
FWROUTE_TABLE_NAME="${PREFIX}fwrt"
FWROUTE_NAME="${PREFIX}fwrn"
FWROUTE_NAME_INTERNET="${PREFIX}fwinternet"
FWIPCONFIG_NAME="${PREFIX}fwconfig"

# Magic Azure Address (https://docs.microsoft.com/en-us/azure/virtual-network/what-is-ip-address-168-63-129-16)
AZURE_DNS_SERVER=168.63.129.16

APPGATEWAY_PUBLICIP=$(echo $PREFIX)-appgateway-ip
APPGATEWAY=$(echo $PREFIX)-appgateway
APPGATEWAY_PROBE=$(echo $PREFIX)-appgateway-probe
APPGATEWAY_PRIVATE_IP_ADDRESS=10.1.0.5

FIREWALL_HTTPBIN_APPLICATION_RULE=httpbin_rule
FIREWALL_HTTPBIN_APPLICATION_RULE_COLLECTION=httpbin_rule_collection

################################################################################
# Create 2 resource groups 
# 1. The HUB for the Firewall (Shared resources)
# 2. The SPOKE for application specific code (website, app gateway, storage)
################################################################################
az group create -n $RG_HUB -l $LOC
az group create -n $RG_SPOKE -l $LOC

################################################################################
# Create 2 networks, HUB and SPOKE, and peer them so communication can flow 
# between then. 
################################################################################
az network vnet create -n $VNET_HUB -g $RG_HUB --address-prefixes $VNET_HUB_IPRANGE
az network vnet create -n $VNET_SPOKE -g $RG_SPOKE --address-prefixes $VNET_SPOKE_IPRANGE

#Create the Subnets in each vnet
az network vnet subnet create -n $APPGATEWAY_SUBNET -g $RG_SPOKE \
    --address-prefixes $APPGATEWAY_SUBNET_IPRANGE --vnet-name $VNET_SPOKE

az network vnet subnet create -n $WEB_SUBNET -g $RG_SPOKE \
    --address-prefixes $WEB_SUBNET_IPRANGE --vnet-name $VNET_SPOKE --service-endpoints "Microsoft.Web"

az network vnet subnet create -n $DATA_SUBNET -g $RG_SPOKE \
    --address-prefixes $DATA_SUBNET_IPRANGE --vnet-name $VNET_SPOKE --service-endpoints "Microsoft.Storage" 

az network vnet subnet update \
  --name $DATA_SUBNET \
  --resource-group $RG_SPOKE \
  --vnet-name $VNET_SPOKE \
  --disable-private-endpoint-network-policies true

az network vnet subnet create -n $FIREWALL_SUBNET -g $RG_HUB \
    --address-prefixes $FIREWALL_SUBNET_IPRANGE --vnet-name $VNET_HUB

#Peer the Vnets
SPOKEID=$(az network vnet show -g $RG_SPOKE -n $VNET_SPOKE --query id -o tsv)
az network vnet peering create -g $RG_HUB -n $HUB_TO_SPOKE_VNET_PEER --vnet-name $VNET_HUB \
    --remote-vnet $SPOKEID --allow-vnet-access

HUBID=$(az network vnet show -g $RG_HUB -n $VNET_HUB --query id -o tsv)
az network vnet peering create -g $RG_SPOKE -n $SPOKE_TO_HUB_VNET_PEER --vnet-name $VNET_SPOKE \
    --remote-vnet $HUBID --allow-vnet-access

################################################################################
# Deploy a storage account, the storage account contains a table populated with 
# 2 records.  The storage account uses a private endpoint to restrict traffic 
# only to the VNET (via a Private DNS Zone)
################################################################################
az storage account create -n $STORAGE -g $RG_SPOKE --https-only

STORAGEKEY=$(az storage account keys list -g $RG_SPOKE -n $STORAGE --query "[?keyName=='key1'].value" --output tsv)

az storage table create -n $TABLE_NAME --account-name $STORAGE --account-key $STORAGEKEY

az storage entity insert --account-name $STORAGE --account-key $STORAGEKEY \
    --entity PartitionKey=AAA RowKey=BBB Content=ASDF2 \
    --if-exists fail --table-name $TABLE_NAME

az storage entity insert --account-name $STORAGE --account-key $STORAGEKEY \
    --entity PartitionKey=AAA RowKey=CCC Content=MDF01 \
    --if-exists fail --table-name $TABLE_NAME

#Update the storage account to lock down to non-authorised Azure traffic 
az storage account update -n $STORAGE -g $RG_SPOKE --https-only --default-action Deny --bypass None

az storage account network-rule add -g $RG_SPOKE --account-name $STORAGE --vnet $VNET_SPOKE --subnet $DATA_SUBNET

#Create a private DNS Zone for table storage
az network private-dns zone create -g $RG_SPOKE -n $TABLE_DNS_ZONE

az network private-dns link vnet create -g $RG_SPOKE -n $STORAGE_DNS_LINK_SPOKE -z $TABLE_DNS_ZONE \
    -v $SPOKEID -e False

az network private-dns link vnet create -g $RG_SPOKE -n $STORAGE_DNS_LINK_HUB -z $TABLE_DNS_ZONE \
    -v $HUBID -e False

#Create a private endpoint connection for the storage account 
STORAGEID=$(az storage account show -n $STORAGE -g $RG_SPOKE --query id -o tsv)
az network private-endpoint create --connection $STORAGE_CONNECTION_NAME -g $RG_SPOKE -n $STORAGE_PRIVATE_ENDPOINT \
    --subnet $DATA_SUBNET --vnet-name $VNET_SPOKE --private-connection-resource-id $STORAGEID --group-ids table

NETWORKINTERFACEID=$(az network private-endpoint show --name $STORAGE_PRIVATE_ENDPOINT --resource-group $RG_SPOKE --query 'networkInterfaces[0].id' -o tsv)

PRIVATEIP=$(az resource show --ids $NETWORKINTERFACEID --api-version 2019-04-01 --query properties.ipConfigurations[0].properties.privateIPAddress -o tsv)
az network private-dns record-set a create --name $PRIVATEIP --zone-name $TABLE_DNS_ZONE --resource-group $RG_SPOKE  
# az network private-dns record-set a add-record --record-set-name $PRIVATEIP --zone-name $TABLE_DNS_ZONE --resource-group $RG_SPOKE -a $PRIVATEIP

az network private-dns record-set a add-record --record-set-name $STORAGE --zone-name $TABLE_DNS_ZONE --resource-group $RG_SPOKE -a $PRIVATEIP

################################################################################
# Create our web application (app plan and website)
# The website is locked down to the vnet and the ip address of the user 
# running the script
################################################################################
az appservice plan create -n $APPPLAN -g $RG_SPOKE --sku S1

#Create the web app on the plan
az webapp create -n $WEBSITE --plan $APPPLAN -g $RG_SPOKE

#Add a managed identity to the web app
az webapp identity assign -g $RG_SPOKE -n $WEBSITE

#Add VNET Integration to the web app
az webapp vnet-integration add -g $RG_SPOKE -n $WEBSITE --vnet $VNET_SPOKE --subnet $WEB_SUBNET

#Get my ip address
MYIP=$(curl http://httpbin.org/ip | jq -r '.origin')

#Add access restictions to my IP only
az webapp config access-restriction add -g $RG_SPOKE -n $WEBSITE --rule-name HomePC --action Allow --ip-address $MYIP --priority 100

#Add my IP to the storage account for debugging
az storage account network-rule add -g $RG_SPOKE --account-name $STORAGE --ip-address $MYIP

# Add the settings
# to route all traffic though the vnet integration (WEBSITE_VNET_ROUTE_ALL)
# to build the application when using git deployment (SCM_DO_BUILD_DURING_DEPLOYMENT)
# the node version (WEBSITE_NODE_DEFAULT_VERSION)
az webapp config appsettings set -g $RG_SPOKE -n $WEBSITE --settings WEBSITE_VNET_ROUTE_ALL=1 SCM_DO_BUILD_DURING_DEPLOYMENT=1 WEBSITE_NODE_DEFAULT_VERSION=10.15.2 WEBSITE_DNS_SERVER=$AZURE_DNS_SERVER

#Write the storage key and account name to app settings
az webapp config appsettings set -g $RG_SPOKE -n $WEBSITE --settings STORAGE_ACCOUNT=$STORAGE STORAGE_KEY=$STORAGEKEY TABLE_NAME=$TABLE_NAME

#Deploy my sample node app to the site
az webapp deployment source config --branch master --manual-integration --name $WEBSITE --repo-url https://github.com/fortunkam/simple-node-express-app --resource-group $RG_SPOKE

################################################################################
# Create the firewall
# The firewall will only allow outgoing traffic to httpbin.org
################################################################################

#Create the firewall public ip
az network public-ip create -g $RG_HUB -n $FWPUBLICIP_NAME -l $LOC --sku "Standard"

# Install Azure Firewall preview CLI extension

az extension add --name azure-firewall

# Deploy Azure Firewall

az network firewall create -g $RG_HUB -n $FWNAME -l $LOC

# Configure Firewall IP Config

az network firewall ip-config create \
    -g $RG_HUB \
    -f $FWNAME \
    -n $FWIPCONFIG_NAME \
    --public-ip-address $FWPUBLICIP_NAME \
    --vnet-name $VNET_HUB

# Capture Firewall IP Address for Later Use

FWPUBLIC_IP=$(az network public-ip show -g $RG_HUB -n $FWPUBLICIP_NAME --query "ipAddress" -o tsv)
FWPRIVATE_IP=$(az network firewall show -g $RG_HUB -n $FWNAME --query "ipConfigurations[0].privateIpAddress" -o tsv)


# Create UDR and add a route for the web subnet (spoke), this ensures all traffic from the web app goes through the firewall
az network route-table create -g $RG_SPOKE --name $FWROUTE_TABLE_NAME
az network route-table route create -g $RG_SPOKE --name $FWROUTE_NAME --route-table-name $FWROUTE_TABLE_NAME --address-prefix 0.0.0.0/0 --next-hop-type VirtualAppliance --next-hop-ip-address $FWPRIVATE_IP --subscription $SUBID

#Ensure all traffic to httpbin.org is allowed (highly locked down)
az network firewall application-rule create \
    --collection-name $FIREWALL_HTTPBIN_APPLICATION_RULE_COLLECTION \
    --name $FIREWALL_HTTPBIN_APPLICATION_RULE \
    --firewall-name $FWNAME \
    -g $RG_HUB \
    --protocols HTTP=80 HTTPS=443 \
    --action Allow \
    --priority 100 \
    --target-fqdns "httpbin.org" \
    --source-addresses "*"

#Add the UDR to the network
az network vnet subnet update -g $RG_SPOKE --vnet-name $VNET_SPOKE --name $WEB_SUBNET --route-table $FWROUTE_TABLE_NAME

################################################################################
# Create the app gateway and configure with a rule to route traffic from the 
# website
################################################################################

#Create the public ip for the app gateway
az network public-ip create \
    -n $APPGATEWAY_PUBLICIP \
    -g $RG_SPOKE \
    --sku Basic

az network application-gateway create \
    -g $RG_SPOKE \
    -n $APPGATEWAY \
    --public-ip-address $APPGATEWAY_PUBLICIP \
    --subnet $APPGATEWAY_SUBNET \
    --vnet-name $VNET_SPOKE \
    --servers "$WEBSITE.azurewebsites.net" \
    --private-ip-address $APPGATEWAY_PRIVATE_IP_ADDRESS

az network application-gateway probe create \
    --gateway-name $APPGATEWAY \
    --name $APPGATEWAY_PROBE \
    --path "/" \
    --protocol Http \
    --resource-group $RG_SPOKE \
    --host-name-from-http-settings true

#Update the http settings to set the host address to the web app name
HTTPSETTING_NAME=$(az network application-gateway http-settings list --gateway-name $APPGATEWAY -g $RG_SPOKE --query "[0].name" -o tsv)
az network application-gateway http-settings update \
    -g $RG_SPOKE \
    --gateway-name $APPGATEWAY \
    --host-name-from-backend-pool true \
    --name $HTTPSETTING_NAME \
    --probe $APPGATEWAY_PROBE

#Update the web site to allow trafic from the app gateway to the web app
APPGATEWAY_PUBLICIP_ADDR=$(az network public-ip show -g $RG_SPOKE -n $APPGATEWAY_PUBLICIP --query "ipAddress" -o tsv)
az webapp config access-restriction add -g $RG_SPOKE -n $WEBSITE --rule-name AppGateway --action Allow --ip-address $APPGATEWAY_PUBLICIP_ADDR --priority 200

ENDDATE=$(date +"%H:%M:%S")
echo "Script Complete: Started at $STARTDATE and ended at $ENDDATE"



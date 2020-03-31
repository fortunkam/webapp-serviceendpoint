#!/bin/bash

################################################################################
# All the required static variables are declared here, most are derived from 
# a common PREFIX 
################################################################################
STARTDATE=$(date +"%H:%M:%S")

PREFIX=mfdns06
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

SE_POLICY=$(echo $PREFIX)-se-policy
SE_STORE_POLICY_DEF=$(echo $PREFIX)-se-store-policy-def

STORAGE_DEPLOY=$(echo $PREFIX)depstore
DEPLOY_SCRIPTS_CONTAINER=scripts

USERLOGIN=AzureAdmin
# User needs to provide a password for the VM (Win 2019 Default Password requirements apply)
read -p 'Administrator Password for VM: ' USERPWD

DNS_PUBLICIP=$(echo $PREFIX)-dns-ip
DNS_VM=$(echo $PREFIX)-dns-vm
DNS_DISK=$(echo $PREFIX)-dns-disk
DNS_INTERNAL_NIC=$(echo $PREFIX)-dns-in-nic
DNS_EXTERNAL_NIC=$(echo $PREFIX)-dns-ext-nic
DNS_PRIVATE_IP_ADDRESS=10.0.1.128

# Magic Azure Address (https://docs.microsoft.com/en-us/azure/virtual-network/what-is-ip-address-168-63-129-16)
AZURE_DNS_SERVER=168.63.129.16

DNS_HTTPBIN_APPLICATION_RULE=httpbin_rule
DNS_HTTPBIN_APPLICATION_RULE_COLLECTION=httpbin_rule_collection

APPGATEWAY_PUBLICIP=$(echo $PREFIX)-appgateway-ip
APPGATEWAY=$(echo $PREFIX)-appgateway
APPGATEWAY_PROBE=$(echo $PREFIX)-appgateway-probe
APPGATEWAY_PRIVATE_IP_ADDRESS=10.1.0.5

################################################################################
# Create 3 resource groups 
# 1. The HUB for the DNS and Firewall (Shared resources)
# 2. The SPOKE for application specific code (website, app gateway, storage)
# 3. DEPLOY for resources required during deployment (e.g. support scripts)
################################################################################
az group create -n $RG_HUB -l $LOC
az group create -n $RG_SPOKE -l $LOC
az group create -n $RG_DEPLOY -l $LOC

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

az network vnet subnet create -n $VM_SUBNET -g $RG_HUB \
    --address-prefixes $VM_SUBNET_IPRANGE --vnet-name $VNET_HUB

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
az webapp config appsettings set -g $RG_SPOKE -n $WEBSITE --settings WEBSITE_VNET_ROUTE_ALL=1 SCM_DO_BUILD_DURING_DEPLOYMENT=1 WEBSITE_NODE_DEFAULT_VERSION=10.15.2

#Write the storage key and account name to app settings
az webapp config appsettings set -g $RG_SPOKE -n $WEBSITE --settings STORAGE_ACCOUNT=$STORAGE STORAGE_KEY=$STORAGEKEY TABLE_NAME=$TABLE_NAME

#Deploy my sample node app to the site
az webapp deployment source config --branch master --manual-integration --name $WEBSITE --repo-url https://github.com/fortunkam/simple-node-express-app --resource-group $RG_SPOKE

################################################################################
# Create the firewall
# The firewall will only allow outgoing traffic to httpbin.org and requests to 
# the DNS server
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

#ensure all DNS traffic to the DNS server is allowed
az network firewall network-rule create -g $RG_HUB -f $FWNAME --collection-name 'dnsrules' -n 'dns' --protocols 'UDP' --source-addresses "$WEB_SUBNET_IPRANGE" --destination-addresses $DNS_PRIVATE_IP_ADDRESS --destination-ports '*' --action allow --priority 100

#Ensure all traffic to httpbin.org is allowed (highly locked down)
az network firewall application-rule create \
    --collection-name $DNS_HTTPBIN_APPLICATION_RULE_COLLECTION \
    --name $DNS_HTTPBIN_APPLICATION_RULE \
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
# Create the DNS Server
# The default Azure DNS server cannot resolve private link address for web apps
# We create out own DNS server and configure a forwarder for the table storage 
# private link address to the azure servers (this is a limitation of the platform 
# and will be fixed) for more information see
# https://github.com/dmauser/PrivateLink/tree/master/DNS-Integration-Scenarios
################################################################################

#Create the DNS Server Public IP (for RDP debugging only!).
az network public-ip create \
    -n $DNS_PUBLICIP \
    -g $RG_HUB \
    --sku Standard

#Create the DNS Server
az vm create \
    -n $DNS_VM \
    -g $RG_HUB \
    --private-ip-address $DNS_PRIVATE_IP_ADDRESS \
    --public-ip-address $DNS_PUBLICIP \
    --os-disk-name $DNS_DISK \
    --admin-username $USERLOGIN \
    --admin-password $USERPWD \
    --assign-identity '[system]' \
    --image Win2019Datacenter \
    --subnet $VM_SUBNET \
    --vnet-name $VNET_HUB

# Deploy a new storage account to hold the deploy scripts

#create a storage account
az storage account create \
    -g $RG_DEPLOY -n $STORAGE_DEPLOY

#get the keys
DEPLOY_STORAGEKEY=$(az storage account keys list -g $RG_DEPLOY -n $STORAGE_DEPLOY --query "[?keyName=='key1'].value" --output tsv)

#create a blob container
az storage container create \
    --name $DEPLOY_SCRIPTS_CONTAINER \
    --public-access off \
    --account-name $STORAGE_DEPLOY \
    --account-key $DEPLOY_STORAGEKEY


# Give the VM persmission to access the blob account 

SCOPE="/subscriptions/$SUBID/resourceGroups/$RG_DEPLOY/providers/Microsoft.Storage/storageAccounts/$STORAGE_DEPLOY"

OBJECTID=$(az vm identity show --name $DNS_VM -g $RG_HUB --query principalId --output tsv) 

az role assignment create --assignee $OBJECTID --role "Storage Blob Data Reader" --scope $SCOPE

#Configure the DNS Server


DEPLOY_DNS_MODULE=DNSServer.zip
DEPLOY_DNS_FILE=DNSServer.ps1
cd scripts
cd DNSServer
zip -r ../../$DEPLOY_DNS_MODULE *
cd ..
cd ..

#upload the files
az storage blob upload \
    -f ./$DEPLOY_DNS_MODULE   \
    -c $DEPLOY_SCRIPTS_CONTAINER \
    -n $DEPLOY_DNS_MODULE \
    --account-name $STORAGE_DEPLOY \
    --account-key $DEPLOY_STORAGEKEY

#Generate a SAS token for our file
SAS_END=`date -u -d "60 minutes" '+%Y-%m-%dT%H:%MZ'`
DEPLOY_SAS_TOKEN=$(az storage blob generate-sas -c $DEPLOY_SCRIPTS_CONTAINER -n $DEPLOY_DNS_MODULE --permissions r --expiry $SAS_END --https-only --account-key $DEPLOY_STORAGEKEY --account-name $STORAGE_DEPLOY)
# Remove the quotes
DEPLOY_SAS_TOKEN=${DEPLOY_SAS_TOKEN:1:${#DEPLOY_SAS_TOKEN}-2}

MODULE_URL="https://$STORAGE_DEPLOY.blob.core.windows.net/$DEPLOY_SCRIPTS_CONTAINER/$DEPLOY_DNS_MODULE?$DEPLOY_SAS_TOKEN"

INSTALL_DNS_SETTINGS=$( jq -n \
                  --arg modurl "$MODULE_URL" \
                  --arg configurationFunction "$DEPLOY_DNS_FILE\\DNSServer" \
                  --arg machineName "$DNS_VM" \
                  '{ModulesURL: $modurl, configurationFunction: $configurationFunction, Properties: { MachineName: $machineName}}' )

#Install DNS Server via DSC

az vm extension set \
   --name DSC \
   --publisher Microsoft.Powershell \
   --version 2.19 \
   --vm-name $DNS_VM \
   --resource-group $RG_HUB \
   --settings "$INSTALL_DNS_SETTINGS" 

az vm restart -g $RG_HUB -n $DNS_VM

#Configure the conditional forwarder zone on the dns server (to point at the table storage DNS name)
CONFIGURE_DNS_ZONE_COMMAND="powershell.exe Add-DnsServerConditionalForwarderZone -Name $STORAGE.table.core.windows.net -MasterServers $AZURE_DNS_SERVER -PassThru"

CONFIGURE_DNS_ZONE=$( jq -n \
                  --arg psCommand "$CONFIGURE_DNS_ZONE_COMMAND" \
                  '{fileUris: [], commandToExecute: $psCommand }' )

az vm extension set \
   --name CustomScriptExtension \
   --publisher Microsoft.Compute \
   --version 1.8 \
   --vm-name $DNS_VM \
   --resource-group $RG_HUB \
   --settings "$CONFIGURE_DNS_ZONE"

#use the DNS server on the vnet

 az vm open-port \
    --port 53 \
    --resource-group $RG_HUB \
    --name $DNS_VM

az network vnet update -g $RG_HUB -n $VNET_HUB --dns-servers $DNS_PRIVATE_IP_ADDRESS

az network vnet update -g $RG_SPOKE -n $VNET_SPOKE --dns-servers $DNS_PRIVATE_IP_ADDRESS

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



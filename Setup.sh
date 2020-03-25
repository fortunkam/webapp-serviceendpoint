PREFIX=mfdns
RG_HUB=$(echo $PREFIX)-hub
RG_SPOKE=$(echo $PREFIX)-spoke
LOC=uksouth

VNET_HUB=$(echo $PREFIX)-hub-vnet
VNET_SPOKE=$(echo $PREFIX)-spoke-vnet

VNET_HUB_IPRANGE=10.0.0.0/16
VNET_SPOKE_IPRANGE=10.1.0.0/16

FIREWALL_SUBNET=firewall
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

STORAGE=$(echo $PREFIX)store
STORAGE_CONNECTION_NAME=$(echo $PREFIX)-private-link
STORAGE_PRIVATE_ENDPOINT=$(echo $PREFIX)-storage-private-endpoint
STORAGE_DNS_LINK=$(echo $PREFIX)-storage-dns-link
TABLE_DNS_ZONE=privatelink.table.core.windows.net

APPPLAN=$(echo $PREFIX)-appplan
WEBSITE=$(echo $PREFIX)-site

#Create 2 resource groups
az group create -n $RG_HUB -l $LOC
az group create -n $RG_SPOKE -l $LOC

#Create 2 networks
az network vnet create -n $VNET_HUB -g $RG_HUB --address-prefixes $VNET_HUB_IPRANGE
az network vnet create -n $VNET_SPOKE -g $RG_SPOKE --address-prefixes $VNET_SPOKE_IPRANGE

#Create the Subnets in each vnet
az network vnet subnet create -n $APPGATEWAY_SUBNET -g $RG_SPOKE \
    --address-prefixes $APPGATEWAY_SUBNET_IPRANGE --vnet-name $VNET_SPOKE

az network vnet subnet create -n $WEB_SUBNET -g $RG_SPOKE \
    --address-prefixes $WEB_SUBNET_IPRANGE --vnet-name $VNET_SPOKE

az network vnet subnet create -n $DATA_SUBNET -g $RG_SPOKE \
    --address-prefixes $DATA_SUBNET_IPRANGE --vnet-name $VNET_SPOKE

az network vnet subnet create -n $FIREWALL_SUBNET -g $RG_HUB \
    --address-prefixes $FIREWALL_SUBNET_IPRANGE --vnet-name $VNET_HUB

az network vnet subnet create -n $VM_SUBNET -g $RG_SPOKE \
    --address-prefixes $VM_SUBNET_IPRANGE --vnet-name $VNET_HUB

#Peer the Vnets
SPOKEID=$(az network vnet show -g $RG_SPOKE -n $VNET_SPOKE --query id -o tsv)
az network vnet peering create -g $RG_HUB -n $HUB_TO_SPOKE_VNET_PEER --vnet-name $VNET_HUB \
    --remote-vnet $SPOKEID --allow-vnet-access

HUBID=$(az network vnet show -g $RG_HUB -n $VNET_HUB --query id -o tsv)
az network vnet peering create -g $RG_SPOKE -n $SPOKE_TO_HUB_VNET_PEER --vnet-name $VNET_SPOKE \
    --remote-vnet $HUBID --allow-vnet-access

#Deploy a storage account
az storage account create -n $STORAGE -g $RG_SPOKE --https-only

#Create a private DNS Zone for table storage
az network private-dns zone create -g $RG_SPOKE -n $TABLE_DNS_ZONE

az network private-dns link vnet create -g $RG_SPOKE -n $STORAGE_DNS_LINK -z $TABLE_DNS_ZONE \
    -v $SPOKEID -e True

#Create a private endpoint connection for the storage account 
STORAGEID=$(az storage account show -n $STORAGE -g $RG_SPOKE --query id -o tsv)
az network private-endpoint create --connection $STORAGE_CONNECTION_NAME -g $RG_SPOKE -n $STORAGE_PRIVATE_ENDPOINT \
    --subnet $DATA_SUBNET --vnet-name $VNET_SPOKE --private-connection-resource-id $STORAGEID --group-ids table

NETWORKINTERFACEID=$(az network private-endpoint show --name $STORAGE_PRIVATE_ENDPOINT --resource-group $RG_SPOKE --query 'networkInterfaces[0].id' -o tsv)

PRIVATEIP=$(az resource show --ids $NETWORKINTERFACEID --api-version 2019-04-01 --query properties.ipConfigurations[0].properties.privateIPAddress -o tsv)
az network private-dns record-set a create --name $PRIVATEIP --zone-name $TABLE_DNS_ZONE --resource-group $RG_SPOKE  
az network private-dns record-set a add-record --record-set-name $PRIVATEIP --zone-name $TABLE_DNS_ZONE --resource-group $RG_SPOKE -a $PRIVATEIP

#Create an App Plan
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

#Create the firewall

#Create a UDR to route all outbound traffic from the web subnet to the firewall

#Confirm site is routing via the firewall

#Create the app gateway

#configure the app gateway

#Create the DNS Server.

#Configure the DNS Server

#Configure the UDR rules



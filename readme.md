# Install an App Service with a service endpoint with outbound traffic routed through a Firewall and inbound traffic coming through an App Gateway.

## Prerequisites: 
For the Azure CLI script I am running them on Ubuntu in the Windows Subsystem for Linux (WSL v1).  I have installed jq to make json parsing a little easier.  To install it yourself use `sudo apt-get install jq`.
To Zip powershell modules ready to upload to blob I am using the zip package `sudo apt install zip`
You will need to provide a password for the DNS VM.  AzureAdmin is the default user name.

## Run the script 
The script can be be found [here](./Setup.sh), it was designed in Ubuntu running on WSL. (Your mileage may vary if you run this on something else). I am running it with `bash setup.sh`  (Note: If you run this on ubuntu with the `sh setup.sh` command it will fail with a Bad Substitution error, this is because I am using a bash specific substring call that is not understood by sh/dash)
The script relies on globally unique names so change the PREFIX variable before you run this.
Make sure you change the LOC varaible to your required region.  (a list of regions can be found by running the following command `az account list-locations --query "[].name" -o tsv`)
Note: The script can take up to 60 minutes to run (provisioning an Application Gateway can take time).

## Clean up
I have added a delete-all script [here](./delete-all.sh) to remove all the resource groups (you will need to tweak the PREFIX variable).  Note: This deletes everything unprompted so be sure you want to use it!  (`bash delete-all.sh`)

## Alternatively use the Terraform script
In the /terraform folder are a selection of tf files.  You will need to have terraform installed (I am running v0.12.24 on Powershell Core 7).
run `terraform init` in a powershell prompt and then run the [setup powershell script here](./terraform/setup.ps1), this script runs the `terraform apply` and then deploys the sample app to the website.
The resource prefix and the location are defined as [variables](./terraform/variables.tf) and you should provide new values (particularly for the prefix). 

## What is the script doing?

![What gets deployed!](/diagrams/What%20gets%20deployed.png "What gets deployed")
The script will create 
- 3 resource groups
- 2 virtual networks (peered)
- 5 subnets
- A storage account with table storage accessible via a private endpoint
- A private DNS zone to allow resolution of the storage private endpoint
- An App Service (Website + plan) running a simple node application, locked down using access restrictions and service endpoints
- A Firewall that all outbound network traffic is routing through
- An App Gateway that all inbound traffic to the app service is routed through.
- A VM hosting a custom DNS Server.

## How does the inbound traffic get routed to my website

![Inbound traffic routing](/diagrams/inbound%20calls.png "inbound calls")

1. A request comes into the Application gateway public ip address.  The App Gateway forwards the request onto the website.
2. The website uses access restrictions to prevent access on the public endpoint to only the ip address of the Application Gateway and the user that ran the script.

## How are internet calls from my website routed?

![outbound internet traffic routing](/diagrams/outbound%20calls%20to%20internet.png "outbound internet traffic routing")

The application that gets deployed makes calls to http://httpbin.org/ip to retrieve the outbound ip of the server making the call.
By default a website with a vnet intergration will always go direct for outbound internet calls (using the app service shared outbound ips).  By adding the `WEBSITE_VNET_ROUTE_ALL=1` setting it will use the UDR applied to the subnet.

1. The website has a VNET Integration to the web subnet.  
2. The web subnet contains a UDR that routes all traffic to the Azure Firewall.
3. The firewall contains application rules that allow traffic to httpbin.org (for the running application), github and npm (for the application build).

The `/ip` route on the website shows the call to httpbin.org/ip is successful and should also return the IP address of the firewall showing the request has been routed.

## How are internet calls to my table storage routed (private endpoint)?

![outbound private endpoint routing](/diagrams/outbound%20calls%20to%20private%20endpoint.png "outbound private endpoint routing")

NOTE: At the current point, App Service Plans with VNET Integration are unable to resolve private endpoint (internal) addresses.  The solution is to deploy a custom DNS with a conditional forwarding zone to allow it to resolve correctly.  In the near future steps 2-4 will not be required.

1. Website requests a MYSTORAGE.table.core.windows.net address.  By default this would resolve to the public ip address (which is locked down)
2. The vnet is configured to point it's DNS requests at our custom DNS Server.
3. The DNS server contains a Conditional Forwarder Zone for MYSTORAGE.table.core.windows.net which points at the Azure DNS address (168.63.129.16) 
https://docs.microsoft.com/en-us/azure/virtual-network/what-is-ip-address-168-63-129-16
4. The Azure DNS is aware of our Private DNS Zone so forwards the request there.
5. The private DNS zone is configured to resolve the privatelink address to an ip address on the vnet.
6. The web app can now communicate directly with the storage account over the private endpoint ip address.

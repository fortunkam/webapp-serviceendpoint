terraform apply -auto-approve
$outputVars = terraform output -json | ConvertFrom-Json

#Add VNET Integration to the web app
az webapp vnet-integration add -g $outputVars.spoke_resource_group.value -n $outputVars.website_name.value --vnet $outputVars.vnet_spoke_name.value --subnet $outputVars.web_subnet.value

#Deploy the app
az webapp deployment source config --branch master --manual-integration --name $outputVars.website_name.value --repo-url https://github.com/fortunkam/simple-node-express-app --resource-group $outputVars.spoke_resource_group.value
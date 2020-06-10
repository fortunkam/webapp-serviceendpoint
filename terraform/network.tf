resource "azurerm_virtual_network" "spoke" {
  name                = local.vnet_spoke_name
  location            = azurerm_resource_group.spoke.location
  resource_group_name = azurerm_resource_group.spoke.name
  address_space       = [local.vnet_spoke_iprange]
}

resource "azurerm_subnet" "appgateway" {
  name                 = local.appgateway_subnet
  resource_group_name  = azurerm_resource_group.spoke.name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefix       = local.appgateway_subnet_iprange
}

resource "azurerm_subnet" "web" {
  name                 = local.web_subnet
  resource_group_name  = azurerm_resource_group.spoke.name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefix       = local.web_subnet_iprange
  service_endpoints = [ "Microsoft.Web" ]

  delegation {
    name = "webdelegation"
    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_subnet" "data" {
  name                 = local.data_subnet
  resource_group_name  = azurerm_resource_group.spoke.name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefix       = local.data_subnet_iprange
  enforce_private_link_endpoint_network_policies = true
  service_endpoints = [ "Microsoft.Storage" ]
}

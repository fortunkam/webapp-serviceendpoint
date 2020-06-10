resource "azurerm_public_ip" "nat" {
  name                = local.nat_publicip
  location            = azurerm_resource_group.spoke.location
  resource_group_name = azurerm_resource_group.spoke.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_public_ip_prefix" "nat" {
  name                = local.nat_publicip_prefix
  location            = azurerm_resource_group.spoke.location
  resource_group_name = azurerm_resource_group.spoke.name
  prefix_length       = 30
}

resource "azurerm_nat_gateway" "nat" {
  name                    = local.nat_gateway_name
  location                = azurerm_resource_group.spoke.location
  resource_group_name     = azurerm_resource_group.spoke.name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 10
}

resource "azurerm_nat_gateway_public_ip_association" "nat" {
  nat_gateway_id       = azurerm_nat_gateway.nat.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

resource "azurerm_subnet_nat_gateway_association" "nat" {
  subnet_id      = azurerm_subnet.web.id
  nat_gateway_id = azurerm_nat_gateway.nat.id
}
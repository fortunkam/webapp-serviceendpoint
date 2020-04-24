resource "azurerm_resource_group" "hub" {
    name     = local.resource_group_hub_name
    location = var.location
}
resource "azurerm_resource_group" "spoke" {
    name     = local.resource_group_spoke_name
    location = var.location
}
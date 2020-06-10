resource "azurerm_resource_group" "spoke" {
    name     = local.resource_group_spoke_name
    location = var.location
}
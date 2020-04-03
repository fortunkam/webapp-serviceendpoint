resource "random_password" "dns_password" {
  keepers = {
    resource_group = azurerm_resource_group.hub.name
  }
  length = 16
  special = true
  override_special = "_%@"
}
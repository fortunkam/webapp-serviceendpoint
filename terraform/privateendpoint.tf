resource "azurerm_private_endpoint" "table" {
  name                = local.storage_data_private_endpoint
  location            = azurerm_resource_group.spoke.location
  resource_group_name = azurerm_resource_group.spoke.name
  subnet_id           = azurerm_subnet.data.id

  private_service_connection {
    name                           = local.storage_data_private_link
    private_connection_resource_id = azurerm_storage_account.data.id
    is_manual_connection           = false
    subresource_names = [ "table" ] 
  }
}
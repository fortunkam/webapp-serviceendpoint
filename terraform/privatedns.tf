resource "azurerm_private_dns_zone" "table" {
  name                = local.storage_table_dns_zone
  resource_group_name = azurerm_resource_group.spoke.name
  depends_on = [azurerm_storage_account.data]
}


resource "azurerm_private_dns_zone_virtual_network_link" "spoke" {
  name                  = local.storage_data_dns_link_spoke
  resource_group_name   = azurerm_resource_group.spoke.name
  private_dns_zone_name = azurerm_private_dns_zone.table.name
  virtual_network_id    = azurerm_virtual_network.spoke.id
}

resource "azurerm_private_dns_a_record" "example" {
  name                = azurerm_storage_account.data.name
  zone_name           = azurerm_private_dns_zone.table.name
  resource_group_name = azurerm_resource_group.spoke.name
  ttl                 = 300
  records             = [ azurerm_private_endpoint.table.private_service_connection[0].private_ip_address ]
}
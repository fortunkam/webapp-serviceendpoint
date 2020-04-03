

resource "azurerm_key_vault" "keyvault" {
  name                        = local.key_vault_name
  location                    = azurerm_resource_group.deploy.location
  resource_group_name         = azurerm_resource_group.deploy.name
  tenant_id                   = data.azurerm_client_config.current.tenant_id

  sku_name = "standard"

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    key_permissions = [
      "get",
    ]

    secret_permissions = [
      "get",
      "set",
      "list",
      "delete"
    ]

    storage_permissions = [
      "get",
    ]
  }

}

resource "azurerm_key_vault_secret" "dnspassword" {
  name         = "DNSPassword"
  value        = random_password.dns_password.result
  key_vault_id = azurerm_key_vault.keyvault.id
}
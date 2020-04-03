resource "azurerm_storage_account" "deploy" {
  name                     = local.storage_deploy
  resource_group_name      = azurerm_resource_group.deploy.name
  location                 = azurerm_resource_group.deploy.location
  account_tier             = "Standard"
  account_replication_type = "GRS"
}

resource "azurerm_storage_account" "data" {
  name                     = local.storage_data
  resource_group_name      = azurerm_resource_group.spoke.name
  location                 = azurerm_resource_group.spoke.location
  account_tier             = "Standard"
  account_replication_type = "GRS"

  network_rules {
    default_action             = "Deny"
    virtual_network_subnet_ids = [azurerm_subnet.data.id]
    # This gets the outbound IP of the user and allows that user to connect to the storage account 
    ip_rules = [ lookup(jsondecode(data.http.httpbin.body), "origin") ]
    bypass                     = ["None"]
  }
}

resource "azurerm_storage_table" "demo" {
  name                 = local.storage_data_table_name
  storage_account_name = azurerm_storage_account.data.name
}

resource "azurerm_storage_table_entity" "demotableentry1" {
  storage_account_name = azurerm_storage_account.data.name
  table_name           = azurerm_storage_table.demo.name

  partition_key = "AAA"
  row_key       = "BBB"

  entity = {
    Content = "ASDF2"
  }
}

resource "azurerm_storage_table_entity" "demotableentry2" {
  storage_account_name = azurerm_storage_account.data.name
  table_name           = azurerm_storage_table.demo.name

  partition_key = "AAA"
  row_key       = "CCC"

  entity = {
    Content = "MDF01"
  }
}

resource "azurerm_storage_container" "scripts" {
  name                  = local.storage_deploy_container_name
  storage_account_name  = azurerm_storage_account.deploy.name
  container_access_type = "private"
}

resource "azurerm_storage_blob" "dnsserverzip" {
  name                   = "DNSServer.zip"
  storage_account_name   = azurerm_storage_account.deploy.name
  storage_container_name = azurerm_storage_container.scripts.name
  type                   = "Block"
  source                 = "${path.module}/../DNSServer.zip"
}

data "azurerm_storage_account_blob_container_sas" "scripts" {
  connection_string = azurerm_storage_account.deploy.primary_connection_string
  container_name    = azurerm_storage_container.scripts.name
  https_only        = true

  start  = "${timestamp()}"
  expiry = "${timeadd(timestamp(), "2h")}"

  permissions {
    read   = true
    add    = false
    create = false
    write  = false
    delete = false
    list   = false
  }
}

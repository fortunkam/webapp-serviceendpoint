resource "azurerm_public_ip" "dns" {
  name                = local.dns_publicip
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# resource "azurerm_network_interface" "dsn_external" {
#   name                = local.dns_external_nic
#   location            = azurerm_resource_group.hub.location
#   resource_group_name = azurerm_resource_group.hub.name

#   ip_configuration {
#     name                          = local.dns_external_ipconfig
    
#     private_ip_address_allocation = "Dynamic"
#     primary = false
#   }
# }
resource "azurerm_network_security_group" "dns" {
  name                = local.dns_nsg
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name
}

resource "azurerm_network_security_rule" "rdp" {
  name                        = "rdp"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "3389"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.hub.name
  network_security_group_name = azurerm_network_security_group.dns.name
}


resource "azurerm_network_interface" "dsn_internal" {
  name                = local.dns_internal_nic
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name
  dns_servers  = [ local.azure_dns_server ]

  ip_configuration {
    name                          = local.dns_internal_ipconfig
    subnet_id                     = azurerm_subnet.vm.id
    private_ip_address_allocation = "Static"
    private_ip_address  = local.dns_server_private_ip
    public_ip_address_id          = azurerm_public_ip.dns.id
    primary = true
  }
}

resource "azurerm_network_interface_security_group_association" "dns" {
  network_interface_id      = azurerm_network_interface.dsn_internal.id
  network_security_group_id = azurerm_network_security_group.dns.id
}

resource "azurerm_virtual_machine" "dns" {
  name                  = local.dns_vm
  location              = azurerm_resource_group.hub.location
  resource_group_name   = azurerm_resource_group.hub.name
  network_interface_ids = [
        azurerm_network_interface.dsn_internal.id
    ]
  vm_size               = "Standard_DS1_v2"

  # Uncomment this line to delete the OS disk automatically when deleting the VM
  # delete_os_disk_on_termination = true

  # Uncomment this line to delete the data disks automatically when deleting the VM
  # delete_data_disks_on_termination = true

  storage_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }
  storage_os_disk {
    name              = local.dns_disk
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }
  os_profile {
    computer_name  = local.dns_vm
    admin_username = var.dns_username
    admin_password = random_password.dns_password.result
  }
  os_profile_windows_config {
      provision_vm_agent        = true
  }

  identity {
      type = "SystemAssigned"
  }
}



resource "azurerm_virtual_machine_extension" "installdns" {
  name                 = "installdns"
  virtual_machine_id   = azurerm_virtual_machine.dns.id
  publisher            = "Microsoft.Powershell"
  type                 = "DSC"
  type_handler_version = "2.19"

  settings = <<SETTINGS
    {
        "ModulesURL": "${azurerm_storage_blob.dnsserverzip.url}${data.azurerm_storage_account_blob_container_sas.scripts.sas}", 
        "configurationFunction": "DNSServer.ps1\\DNSServer", 
        "Properties": 
        { 
            "MachineName": "${local.dns_vm}"
        }
    }
SETTINGS

    lifecycle {
        ignore_changes = [
            settings
        ]
    }
}

resource "azurerm_virtual_machine_extension" "configuredns" {
  name                 = "configuredns"
  virtual_machine_id   = azurerm_virtual_machine.dns.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.8"

  settings = <<SETTINGS
    {
        "fileUris": [], 
        "commandToExecute": "powershell.exe Add-DnsServerConditionalForwarderZone -Name ${local.storage_data}.table.core.windows.net -MasterServers ${local.azure_dns_server} -PassThru"
    }
SETTINGS

    depends_on = [azurerm_virtual_machine_extension.installdns]
}

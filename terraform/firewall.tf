resource "azurerm_public_ip" "firewall" {
  name                = local.firewall_publicip
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_firewall" "firewall" {
  name                = local.firewall_name
  location            = azurerm_resource_group.hub.location
  resource_group_name = azurerm_resource_group.hub.name

  ip_configuration {
    name                 = local.firewall_ipconfig_name
    subnet_id            = azurerm_subnet.firewall.id
    public_ip_address_id = azurerm_public_ip.firewall.id
  }
}

resource "azurerm_firewall_network_rule_collection" "dns" {
  name                = "dnsrules"
  azure_firewall_name = azurerm_firewall.firewall.name
  resource_group_name = azurerm_resource_group.hub.name
  priority            = 100
  action              = "Allow"

  rule {
    name = "dns"

    source_addresses = [
      local.web_subnet_iprange
    ]

    destination_ports = [
      "*",
    ]

    destination_addresses = [
      local.dns_server_private_ip
    ]

    protocols = [
      "UDP",
    ]
  }
}

resource "azurerm_firewall_application_rule_collection" "httpbin" {
  name                = local.dns_httpbin_application_rule_collection
  azure_firewall_name = azurerm_firewall.firewall.name
  resource_group_name = azurerm_resource_group.hub.name
  priority            = 100
  action              = "Allow"

  rule {
    name = local.dns_httpbin_application_rule

    source_addresses = [
      "*",
    ]

    target_fqdns = [
      "httpbin.org",
    ]

    protocol {
      port = "443"
      type = "Https"
    }

    protocol {
      port = "80"
      type = "Http"
    }
  }
}

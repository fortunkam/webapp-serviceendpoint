resource "azurerm_public_ip" "gateway" {
  name                = local.appgateway_publicip
  location            = azurerm_resource_group.spoke.location
  resource_group_name = azurerm_resource_group.spoke.name
  allocation_method   = "Dynamic"
  sku                 = "Basic"
}

resource "azurerm_application_gateway" "appgateway" {
  name                = local.appgateway
  resource_group_name = azurerm_resource_group.spoke.name
  location            = azurerm_resource_group.spoke.location

  sku {
    name     = "Standard_Small"
    tier     = "Standard"
    capacity = 2
  }

  gateway_ip_configuration {
    name      = local.appgateway_ipconfig_name
    subnet_id = azurerm_subnet.appgateway.id
  }

  frontend_port {
    name = local.appgateway_frontend_port_name
    port = 80
  }

  frontend_ip_configuration {
    name                 = local.appgateway_frontend_ip_configuration_name
    public_ip_address_id = azurerm_public_ip.gateway.id
    private_ip_address  = local.appgateway_private_ip_address
  }

  probe {
      name = local.appgateway_probe
      pick_host_name_from_backend_http_settings = true
      protocol = "Http"
      interval = 120
      path = "/"
      unhealthy_threshold = 1
      timeout = 5
  }

  backend_address_pool {
    name = local.appgateway_backend_pool_name
    fqdns = [
        "${local.website}.azurewebsites.net"
    ]
  }

  backend_http_settings {
    name                  = local.appgateway_http_setting_name
    cookie_based_affinity = "Disabled"
    path                  = "/"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 1
    pick_host_name_from_backend_address = true
    probe_name              = local.appgateway_probe
  }

  http_listener {
    name                           = local.appgateway_listener_name
    frontend_ip_configuration_name = local.appgateway_frontend_ip_configuration_name
    frontend_port_name             = local.appgateway_frontend_port_name
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = local.appgateway_request_routing_rule_name
    rule_type                  = "Basic"
    http_listener_name         = local.appgateway_listener_name
    backend_address_pool_name  = local.appgateway_backend_pool_name
    backend_http_settings_name = local.appgateway_http_setting_name
  }
}
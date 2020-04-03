data "archive_file" "dnsserverzip" {
  type        = "zip"
  source_file = "${path.module}/../scripts/DNSServer/DNSServer.ps1"
  output_path = "${path.module}/../DNSServer.zip"
}

data "http" "httpbin" {
    url = "http://httpbin.org/ip"
    
    request_headers = {
        Accept = "application/json"
    }
}

data "azurerm_client_config" "current" {
}
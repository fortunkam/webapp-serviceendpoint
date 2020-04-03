output "dns_password" {
    value = random_password.dns_password.result
}

output "spoke_resource_group" {
    value = local.resource_group_spoke_name
}

output "website_name" {
    value = local.website
}

output "vnet_spoke_name" {
    value = local.vnet_spoke_name
}

output "web_subnet" {
    value = local.web_subnet
}
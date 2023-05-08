output "resource_group_name" {
  value = azurerm_resource_group.rg00.name
}

output "ip_address" {
  value = azurerm_public_ip.pip00[*].ip_address
}

output "domain_name_label" {
  value = azurerm_public_ip.pip00[*].domain_name_label
}

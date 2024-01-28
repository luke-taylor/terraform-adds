output "subnets" {
  value = tolist(azurerm_virtual_network.this.subnet)
}

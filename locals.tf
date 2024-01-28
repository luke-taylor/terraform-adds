locals {
  domain = "ad.luketaylor.cloud"
  ip_addresses = ["10.0.0.196",
  "10.0.0.197"]

  subnets = {
    for subnet in azurerm_virtual_network.this.subnet : subnet.name => {
      id = subnet.id
    }
  }
}


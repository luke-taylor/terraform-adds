resource "azurerm_resource_group" "identity_eus" {
  name     = "rg-identity-eus"
  location = "eastus"
}

resource "azurerm_resource_group" "network_eus" {
  name     = "rg-network-eus"
  location = "eastus"
}

resource "azurerm_resource_group" "avd_eus" {
  name     = "rg-avd-eus"
  location = "eastus"
}

resource "azurerm_resource_group" "avd_jw" {
  name     = "rg-avd-jw"
  location = "japanwest"
}

resource "azurerm_resource_group" "avd_uks" {
  name     = "rg-avd-uks"
  location = "uksouth"
}

resource "azurerm_virtual_network" "this" {
  name                = "vnet-network-eus"
  location            = azurerm_resource_group.network_eus.location
  resource_group_name = azurerm_resource_group.network_eus.name
  dns_servers         = setunion(local.ip_addresses, ["168.63.129.16"])

  address_space = ["10.0.0.0/21"]

  subnet {
    name           = "GatewaySubnet"
    address_prefix = "10.0.0.0/26"
  }

  subnet {
    name           = "AzureFirewallSubnet"
    address_prefix = "10.0.0.64/26"
  }

  subnet {
    name           = "AzureBastionSubnet"
    address_prefix = "10.0.0.128/26"
  }

  subnet {
    name           = "snet-identity-eus"
    address_prefix = "10.0.0.192/26"
  }
}

resource "azurerm_public_ip" "this" {
  name                = "pip-bastion-eus"
  location            = azurerm_resource_group.network_eus.location
  allocation_method   = "Static"
  resource_group_name = azurerm_resource_group.network_eus.name
  sku                 = "Standard"
}

resource "azurerm_bastion_host" "this" {
  name                = "bastion-network-eus"
  location            = azurerm_resource_group.network_eus.location
  resource_group_name = azurerm_resource_group.network_eus.name

  ip_configuration {
    name                 = "IpConf"
    subnet_id            = local.subnets["AzureBastionSubnet"].id
    public_ip_address_id = azurerm_public_ip.this.id
  }
}

resource "azurerm_availability_set" "example" {
  name                = "as-dc-eus"
  location            = azurerm_resource_group.identity_eus.location
  resource_group_name = azurerm_resource_group.identity_eus.name

  platform_fault_domain_count  = 2
  platform_update_domain_count = 2
}

resource "azurerm_network_interface" "example" {
  count = 2

  name                = "nic-dc-eus-${count.index}"
  location            = azurerm_resource_group.identity_eus.location
  resource_group_name = azurerm_resource_group.identity_eus.name

  ip_configuration {
    name                          = "ipConfig0"
    private_ip_address_allocation = "Static"
    private_ip_address            = local.ip_addresses[count.index]
    subnet_id                     = local.subnets["snet-identity-eus"].id
  }
}

resource "azurerm_windows_virtual_machine" "example" {
  count = 2

  name                  = "vm-dc-eus-${count.index}"
  location              = azurerm_resource_group.identity_eus.location
  resource_group_name   = azurerm_resource_group.identity_eus.name
  network_interface_ids = [azurerm_network_interface.example[count.index].id]
  size                  = "Standard_B2s"
  availability_set_id   = azurerm_availability_set.example.id



  computer_name  = "vm-dc-eus-${count.index}"
  admin_username = var.vm_username
  admin_password = var.vm_password


  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2016-Datacenter"
    version   = "latest"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }


  depends_on = [
    azurerm_network_interface.example,
    azurerm_availability_set.example,
  ]

}

resource "azurerm_public_ip" "nat" {
  name                = "pip-nat-eus"
  location            = azurerm_resource_group.network_eus.location
  resource_group_name = azurerm_resource_group.network_eus.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_nat_gateway" "this" {
  location            = azurerm_resource_group.network_eus.location
  name                = "natgw-network-eus"
  resource_group_name = azurerm_resource_group.network_eus.name
}

resource "azurerm_subnet_nat_gateway_association" "example" {
  subnet_id      = local.subnets["snet-identity-eus"].id
  nat_gateway_id = azurerm_nat_gateway.this.id
}

resource "azurerm_nat_gateway_public_ip_association" "example" {
  nat_gateway_id       = azurerm_nat_gateway.this.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

resource "azurerm_virtual_machine_extension" "example_dc_01" {
  name                 = "vm-dc-eus-0-DSC"
  virtual_machine_id   = azurerm_windows_virtual_machine.example[0].id
  publisher            = "Microsoft.Powershell"
  type                 = "DSC"
  type_handler_version = "2.77"

  auto_upgrade_minor_version = true

  protected_settings = <<SETTINGS
    {
      "Items": {
        "VmPassword": "${var.vm_password}"
      }
    }
SETTINGS

  settings = <<SETTINGS
    {
      "wmfVersion": "latest",
      "modulesUrl": "https://github.com/microsoft/WhatTheHack/raw/master/037-AzureVirtualDesktop/Student/Resources/dsc/ActiveDirectoryForest.zip",
      "configurationFunction": "ActiveDirectoryForest.ps1\\ActiveDirectoryForest",
      "properties": {
        "Domain": "${local.domain}",
        "DomainCreds": {
          "UserName": "${var.vm_username}",
          "Password": "PrivateSettingsRef:VmPassword"
        }
      }
    }
SETTINGS
}

resource "azurerm_virtual_machine_extension" "example_dc_02" {
  name                 = "vm-dc-eus-1-DSC"
  virtual_machine_id   = azurerm_windows_virtual_machine.example[1].id
  publisher            = "Microsoft.Powershell"
  type                 = "DSC"
  type_handler_version = "2.77"

  auto_upgrade_minor_version = true

  depends_on = [azurerm_virtual_machine_extension.example_dc_01]

  protected_settings = <<SETTINGS
  {
    "configurationArguments": {
      "safemodeAdminCreds": {
        "UserName": "${var.vm_username}",
        "Password": "${var.vm_password}"
      },
      "adminCreds": {
        "UserName": "${var.vm_username}",
        "Password": "${var.vm_password}"
      }
    }
  }
SETTINGS

  settings = <<SETTINGS
  {
    "configuration": {
      "WMFVersion": "latest",
      "url": "https://github.com/luke-taylor/terraform-adds/raw/main/dsc/promote-adds.zip",
      "script": "promote-adds.ps1",
      "function": "CreateADReplicaDC"
    },
    "configurationArguments": {
      "DomainName": "${local.domain}"
    }
  }
SETTINGS
}



terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.0.0"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-resources"
  location = "North Europe"
  tags = {
    environment = "dev"
  }
}

resource "azurerm_virtual_network" "vnet" {
  name                = "dev-virtual-network"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.1.0.0/16"]
  tags = {
    environment = "dev"
  }
}

resource "azurerm_subnet" "subnet" {
  name                 = "first-sub-network"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.1.1.0/24"]

}

resource "azurerm_network_security_group" "nsg" {
  name                = "network-security-group"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  tags = {
    environment = "dev"
  }
}

resource "azurerm_network_security_rule" "nsr" {
  name                        = "dev-rule"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.rg.name
  network_security_group_name = azurerm_network_security_group.nsg.name
}

resource "azurerm_subnet_network_security_group_association" "nsga" {
  subnet_id                 = azurerm_subnet.subnet.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_public_ip" "ip" {
  name                = "ip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Dynamic"

  tags = {
    environment = "dev"
  }
}

resource "azurerm_network_interface" "nic" {
  name                = "nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "Internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.ip.id
  }

  tags = {
    environment = "dev"
  }
}

resource "azurerm_linux_virtual_machine" "lvm" {
  name                = "vm"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = "Standard_B1s"
  admin_username      = "adminuser"
  network_interface_ids = [
    azurerm_network_interface.nic.id
  ]

  custom_data = filebase64("customdata.tpl")

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  admin_ssh_key {
    username   = "adminuser"
    public_key = file("C:/Users/spiro/.ssh/tfazurekey.pub.pub")
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "22_04-lts"
    version   = "latest"
  }

  provisioner "local-exec" {
    command = templatefile("${var.host_os}-ssh-script.tpl", {
      hostname     = self.public_ip_address,
      user         = "adminuser"
      identityfile = "~/.ssh/tfazurekey"
    })
    interpreter = ["Powershell", "-Command"]
  }

  tags = {
    environment = "dev"
  }
}

data "azurerm_public_ip" "ip_data" {
  name = azurerm_public_ip.ip.name
  resource_group_name = azurerm_resource_group.rg.name
}

output "public_pi_address" {
  value = "${azurerm_linux_virtual_machine.lvm.name}: ${data.azurerm_public_ip.ip_data.ip_address}"
}
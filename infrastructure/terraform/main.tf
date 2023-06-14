terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=2.97.0"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "shawbrook-interview" {
  name     = "interview"
  location = "UK South"
  tags = {
    environment = "dev"
  }
}

resource "azurerm_virtual_network" "hr-app-vnet" {
  name                = "hr-app-vnet"
  resource_group_name = azurerm_resource_group.shawbrook-interview.name
  location            = azurerm_resource_group.shawbrook-interview.location
  address_space       = ["10.123.0.0/16"]

  tags = {
    environment = "dev"
  }
}

resource "azurerm_subnet" "hr-app-subnet" {
  name                 = "hr-app-subnet"
  resource_group_name  = azurerm_resource_group.shawbrook-interview.name
  virtual_network_name = azurerm_virtual_network.hr-app-vnet.name
  address_prefixes     = ["10.123.1.0/24"]
}

resource "azurerm_network_security_group" "hr-app-nsg" {
  name                = "hr-app-nsg"
  location            = azurerm_resource_group.shawbrook-interview.location
  resource_group_name = azurerm_resource_group.shawbrook-interview.name

  tags = {
    environment = "dev"
  }
}

resource "azurerm_network_security_rule" "net-sec-rule" {
  name                        = "net-sec-rule"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.shawbrook-interview.name
  network_security_group_name = azurerm_network_security_group.hr-app-nsg.name
}

resource "azurerm_subnet_network_security_group_association" "hr-app-sga" {
  subnet_id                 = azurerm_subnet.hr-app-subnet.id
  network_security_group_id = azurerm_network_security_group.hr-app-nsg.id
}

resource "azurerm_public_ip" "hr-app-publicip" {
  name                = "hr-app-publicip"
  resource_group_name = azurerm_resource_group.shawbrook-interview.name
  location            = azurerm_resource_group.shawbrook-interview.location
  allocation_method   = "Dynamic"

  tags = {
    environment = "dev"
  }
}

resource "azurerm_network_interface" "hr-app-vm372_z1" {
  name                = "hr-app-nic"
  location            = azurerm_resource_group.shawbrook-interview.location
  resource_group_name = azurerm_resource_group.shawbrook-interview.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.hr-app-subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.hr-app-publicip.id
  }

  tags = {
    environment = "dev"
  }
}

resource "azurerm_linux_virtual_machine" "hr-app-vm" {
  name                  = "hr-app-vm"
  resource_group_name   = azurerm_resource_group.shawbrook-interview.name
  location              = azurerm_resource_group.shawbrook-interview.location
  size                  = "Standard_B1s"
  admin_username        = "adminuser"
  network_interface_ids = [azurerm_network_interface.hr-app-vm372_z1.id]

  custom_data = filebase64("customdata.tpl")

  admin_ssh_key {
    username   = "adminuser"
    public_key = file("~/.ssh/hr-app-vm_key.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  provisioner "local-exec" {
    command = templatefile("${var.host_os}-ssh-script.tpl", {
      hostname = self.public_ip_address,
      user = "adminuser",
      identityfile = "~/.ssh/hr-app-vm_key"
    })
    interpreter = var.host_os == "windows" ? ["Powershell", "-Command"] : ["bash", "-c"]
  }

  tags = {
    environment = "dev"
  }
}

data "azurerm_public_ip" "hr-app-ip-data" {
  name = azurerm_public_ip.hr-app-publicip.name
  resource_group_name = azurerm_resource_group.shawbrook-interview.name
}

output "public_ip_address" {
  value = "${azurerm_linux_virtual_machine.hr-app-vm.name}: ${data.azurerm_public_ip.hr-app-ip-data.ip_address}"
}
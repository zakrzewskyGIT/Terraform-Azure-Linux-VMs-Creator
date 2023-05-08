# Configure the Azure provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0.2"
    }
  }
  required_version = ">= 1.1.0"
}
provider "azurerm" {
  features {}
}
# Create Resource Group
resource "azurerm_resource_group" "rg00" {
  name     = "${var.resource_prefix}-rg"
  location = var.node_location
}
# Create a virtual network
resource "azurerm_virtual_network" "vnet00" {
  name                = "${var.resource_prefix}-vnet"
  resource_group_name = azurerm_resource_group.rg00.name
  address_space       = var.node_address_space
  location            = var.node_location
}
# Create subnet
resource "azurerm_subnet" "subnet00" {
  name                 = "${var.resource_prefix}-subnet"
  resource_group_name  = azurerm_resource_group.rg00.name
  virtual_network_name = azurerm_virtual_network.vnet00.name
  address_prefixes     = var.node_address_prefix
}
# Create Linux Public IP
resource "azurerm_public_ip" "pip00" {
  count               = var.node_count
  name                = "${var.resource_prefix}-${format("%02d", count.index)}-pip"
  location            = azurerm_resource_group.rg00.location
  resource_group_name = azurerm_resource_group.rg00.name
  allocation_method   = "Static"
  domain_name_label   = "${var.resource_prefix}-${count.index}"
  tags = {
    environment = var.tag_environment
  }
}
# Create network interface
resource "azurerm_network_interface" "nic00" {
  count = var.node_count
  name                = "${var.resource_prefix}-${format("%02d", count.index)}-nic"
  location            = azurerm_resource_group.rg00.location
  resource_group_name = azurerm_resource_group.rg00.name
  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet00.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = element(azurerm_public_ip.pip00.*.id, count.index)
  }
}

# Create Network Security Group and rule
resource "azurerm_network_security_group" "nsg00" {
  name                = "${var.resource_prefix}-nsg"
  location            = azurerm_resource_group.rg00.location
  resource_group_name = azurerm_resource_group.rg00.name
  security_rule {
    name                       = "Inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = var.nsg_source_address_prefix
    destination_address_prefix = "*"
  }
}

# Connect the security group to the network interface
resource "azurerm_subnet_network_security_group_association" "subnet00_nsg_association" {
    subnet_id = azurerm_subnet.subnet00.id
    network_security_group_id = azurerm_network_security_group.nsg00.id
}

# Virtual Machine
resource "azurerm_virtual_machine" "linuxvm00" {
  count = var.node_count
  name = "${var.resource_prefix}-${format("%02d", count.index)}-vm"
  location = azurerm_resource_group.rg00.location
  resource_group_name = azurerm_resource_group.rg00.name
  network_interface_ids = [element(azurerm_network_interface.nic00.*.id, count.index)]

  vm_size = var.vm_size
  delete_data_disks_on_termination = true

  storage_image_reference {
    publisher = var.image_publisher
    offer     = var.image_offer
    sku       = var.image_sku
    version   = var.image_version
  }
  storage_os_disk {
    name = "${var.resource_prefix}-${format("%02d", count.index)}-os"
    caching = "ReadWrite"
    create_option = "FromImage"
    managed_disk_type = var.disk_managed_disk_type
  }

  os_profile {
    computer_name  = "${var.resource_prefix}-${format("%02d", count.index)}"
    admin_username = var.vm_username
    admin_password = var.vm_password
  }
  os_profile_linux_config {
    disable_password_authentication = false
  }

  provisioner "remote-exec" {
    connection {
      host        = azurerm_public_ip.pip00[count.index].ip_address
      type        = "ssh"
      user        = var.vm_username
      password    = var.vm_password
      agent       = false
      private_key = file("~/.ssh/id_rsa")
    }
    inline = [
      #"sudo apt-get update",
      #"sudo apt-get install -y htop",
      #"echo 'hello world' > /home/${var.vm_username}/hello",
      "echo ${var.public_key} >> /home/${var.vm_username}/.ssh/authorized_keys"
    ]
  }
  tags = {
    "environment" = var.tag_environment
  }
}

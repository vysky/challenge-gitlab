terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>2.0"
    }
  }
}

provider "azurerm" {
  features {}
  skip_provider_registration = true
}

/* ---------- variables ---------- */

variable "rg" {
  default = ""
}

variable "location" {
  default = "eastus"
}

# generate random string for domain_name_label under public ip
resource "random_string" "fqdn" {
  length  = 6
  special = false
  upper   = false
  number  = false
}

/* ---------- network ---------- */

# create virtual network
resource "azurerm_virtual_network" "main" {
  name                = "skynet"
  address_space       = ["10.0.0.0/16"]
  location            = var.location
  resource_group_name = var.rg
}

# create subnet
resource "azurerm_subnet" "internal" {
  name                 = "internal"
  resource_group_name  = var.rg
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.10.0/24"]
}

# create public ip
resource "azurerm_public_ip" "gitlab-publicip" {
  name                = "gitlab-publicip"
  resource_group_name = var.rg
  location            = var.location
  allocation_method   = "Static"
  domain_name_label   = random_string.fqdn.result
}

# create network security group
resource "azurerm_network_security_group" "gitlab-nsg" {
  name                = "gitlab-nsg"
  location            = var.location
  resource_group_name = var.rg

  security_rule {
    name                       = "default"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# create network interface
resource "azurerm_network_interface" "main" {
  name                = "skynet-nic"
  location            = var.location
  resource_group_name = var.rg

  ip_configuration {
    name                          = "default"
    subnet_id                     = azurerm_subnet.internal.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.gitlab-publicip.id
  }
}

/* ---------- vm ---------- */

# create vm
resource "azurerm_virtual_machine" "gitlab-vm" {
  name                  = "gitlab-vm"
  resource_group_name   = var.rg
  location              = var.location
  vm_size               = "Standard_D2s_v3"
  network_interface_ids = [azurerm_network_interface.main.id]

  plan {
    publisher = "gitlabinc1586447921813"
    product   = "gitlabee"
    name      = "default"
  }

  storage_image_reference {
    publisher = "gitlabinc1586447921813"
    offer     = "gitlabee"
    sku       = "default"
    version   = "latest"
  }

  os_profile {
    computer_name  = "gitlab-host"
    admin_username = "gitlabadmin"
    admin_password = "Qwerty123!"
  }

  os_profile_linux_config {
    disable_password_authentication = false
  }

  storage_os_disk {
    name              = "maindisk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Premium_LRS"
  }
}
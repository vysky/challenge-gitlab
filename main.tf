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
  default = "1-070f4087-playground-sandbox"
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

# create network security group
resource "azurerm_network_security_group" "main" {
  name                = "gitlab-nsg"
  resource_group_name = var.rg
  location            = var.location

  # allow all inbound traffic
  security_rule {
    name                       = "rule-inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # allow all outbound traffic
  security_rule {
    name                       = "rule-outbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# create public ip
resource "azurerm_public_ip" "main" {
  name                = "gitlab-publicip"
  resource_group_name = var.rg
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard" # require "standard" if using availability zone
  availability_zone   = 1 # allocate the public ip in availability zone 1
  domain_name_label   = random_string.fqdn.result
}

# create virtual network
resource "azurerm_virtual_network" "main" {
  name                = "gitlab-vn"
  address_space       = ["10.0.0.0/16"]
  resource_group_name = var.rg
  location            = var.location
}

# create subnet
resource "azurerm_subnet" "main" {
  name                 = "gitlab-subnet"
  resource_group_name  = var.rg
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.10.0/24"]
}

# create network interface
resource "azurerm_network_interface" "main" {
  name                = "gitlab-nic"
  resource_group_name = var.rg
  location            = var.location

  ip_configuration {
    name                          = "default"
    subnet_id                     = azurerm_subnet.main.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.main.id # to associate the nic with the created public ip
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
  zones                 = [1]

  # required if use azure platform image from azure marketplace
  plan {
    publisher = "gitlabinc1586447921813"
    product   = "gitlabee"
    name      = "default"
  }

  # to provision the vm with azure platform image from azure marketplace
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
    name              = "gitlab-disk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Premium_LRS"
  }
}

/* ---------- output ---------- */

output "public_ip" {
  value = azurerm_public_ip.main.ip_address
}

output "fqdn" {
  value = azurerm_public_ip.main.fqdn
}
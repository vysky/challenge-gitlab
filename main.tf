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

variable "username" {
  default = "azureuser"
}

variable "password" {
  default = "Qwerty123456!"
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

  security_rule {
    name                       = "AllowAllInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowAllOutbound"
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
  availability_zone   = 1          # allocate the public ip in availability zone 1
  domain_name_label   = random_string.fqdn.result
}

# create virtual network
resource "azurerm_virtual_network" "main" {
  name                = "gitlab-vn"
  resource_group_name = var.rg
  location            = var.location
  address_space       = ["10.0.0.0/16"]

  /*
  # aleternative way to create subnet and associate nsg
  subnet {
    name           = "gitlab-subnet"
    address_prefix = ["10.0.10.0/24"]
    security_group = azurerm_network_security_group.main.id # # associate the created nsg with subnet
  }
  */
}

# create subnet
resource "azurerm_subnet" "main" {
  name                 = "gitlab-subnet"
  resource_group_name  = var.rg
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.10.0/24"]
}

# associate nsg with subnet
resource "azurerm_subnet_network_security_group_association" "main" {
  subnet_id                 = azurerm_subnet.main.id
  network_security_group_id = azurerm_network_security_group.main.id
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
  name                          = "gitlab-vm"
  resource_group_name           = var.rg
  location                      = var.location
  vm_size                       = "Standard_D2s_v3"
  network_interface_ids         = [azurerm_network_interface.main.id]
  delete_os_disk_on_termination = true # delete os disk automatically when deleting vm
  zones                         = [1]  # allocate the vm in availability zone 1, need to be in the same zone as public ip

  # require if using azure platform image from azure marketplace
  plan {
    publisher = "gitlabinc1586447921813"
    product   = "gitlabee"
    name      = "default"
  }

  # provision the vm with azure platform image from azure marketplace
  storage_image_reference {
    publisher = "gitlabinc1586447921813"
    offer     = "gitlabee"
    sku       = "default"
    version   = "latest"
  }

  os_profile {
    computer_name  = "gitlab-host"
    admin_username = var.username
    admin_password = var.password
  }

  os_profile_linux_config {
    disable_password_authentication = false
  }

  storage_os_disk {
    name              = "gitlab-os-disk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Premium_LRS"
  }
}

/* ---------- output ---------- */

output "public_ip" {
  value = azurerm_public_ip.main.ip_address
}

output "private_ip" {
  value = azurerm_network_interface.main.private_ip_address
}

output "fqdn" {
  value = azurerm_public_ip.main.fqdn
}

/* ---------- ansible ---------- */

resource "local_file" "inventory" {
  content  = azurerm_public_ip.main.ip_address
  filename = "./inventory"
  file_permission = "0644"
}

resource "local_file" "fqdn" {
  content  = azurerm_public_ip.main.fqdn
  filename = "./fqdn"
  file_permission = "0644"
}

resource "local_file" "password" {
  content  = var.password
  filename = "./password"
  file_permission = "0644"
}

/*
resource "null_resource" "ansible" {
  connection {
    type     = "ssh"
    user     = var.username
    password = var.password
    host     = azurerm_public_ip.main.ip_address
  }

  provisioner "terraforemote-exec" {
    inline = ["ansible-playbook main.yml"]
  }
}
*/
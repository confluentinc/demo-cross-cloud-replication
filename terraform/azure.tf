
locals {
  dns_domain = confluent_private_link_attachment.destpla.dns_domain
  network_id = split(".", confluent_private_link_attachment.destpla.dns_domain)[0]
}

# Resource Group
resource "azurerm_resource_group" "rg" {
  name     = "${var.prefix}-rg"
  location = var.azure_region
}

# Virtual Network
resource "azurerm_virtual_network" "vnet" {
  name                = "${var.prefix}-vnet"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  address_space       = ["10.0.0.0/16"]
}

# Public Subnet
resource "azurerm_subnet" "public" {
  name                 = "${var.prefix}-public-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Private Subnet
resource "azurerm_subnet" "private" {
  name                 = "${var.prefix}-private-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]
}

# Public IP for VM
resource "azurerm_public_ip" "vm_public_ip" {
  name                = "${var.prefix}-vm-public-ip"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  allocation_method   = "Static"
}

# Network Security Group for Public Subnet
resource "azurerm_network_security_group" "public_nsg" {
  name                = "${var.prefix}-public-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "RDP"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "HTTP"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "HTTPS"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Network Security Group for Private Subnet
resource "azurerm_network_security_group" "private_nsg" {
  name                = "${var.prefix}-private-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "AllowVnetInBound"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }
}

# Associate NSG with Public Subnet
resource "azurerm_subnet_network_security_group_association" "public_nsg_association" {
  subnet_id                 = azurerm_subnet.public.id
  network_security_group_id = azurerm_network_security_group.public_nsg.id
}

# Associate NSG with Private Subnet
resource "azurerm_subnet_network_security_group_association" "private_nsg_association" {
  subnet_id                 = azurerm_subnet.private.id
  network_security_group_id = azurerm_network_security_group.private_nsg.id
}



resource "azurerm_private_dns_zone" "hz" {
  resource_group_name = azurerm_resource_group.rg.name
  name                = local.dns_domain
}

resource "azurerm_private_endpoint" "endpoint" {
  name                = "confluent-${local.network_id}-${random_id.env_display_id.hex}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  subnet_id = azurerm_subnet.private.id

  private_service_connection {
    name                              = "confluent-${local.network_id}-${random_id.env_display_id.hex}"
    is_manual_connection              = true
    private_connection_resource_alias = confluent_private_link_attachment.destpla.azure[0].private_link_service_alias
    request_message                   = "PL"
  }
}

resource "azurerm_private_dns_zone_virtual_network_link" "hz" {
  name                  = azurerm_virtual_network.vnet.name
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.hz.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
}

resource "azurerm_private_dns_a_record" "rr" {
  name                = "*"
  zone_name           = azurerm_private_dns_zone.hz.name
  resource_group_name = azurerm_resource_group.rg.name
  ttl                 = 60
  records = [
    azurerm_private_endpoint.endpoint.private_service_connection[0].private_ip_address
  ]
}

# Network Interface for VM (place this after your public IP resource)
resource "azurerm_network_interface" "vm_nic" {
  name                = "${var.prefix}-vm-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.public.id  # This places the VM in the public subnet
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm_public_ip.id
  }
}

# Associate Network Security Group to the network interface
resource "azurerm_network_interface_security_group_association" "vm_nsg_association" {
  network_interface_id      = azurerm_network_interface.vm_nic.id
  network_security_group_id = azurerm_network_security_group.public_nsg.id
}

resource "azurerm_windows_virtual_machine" "vm" {
  name                = "${var.prefix}-vm"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = "Standard_B2ms"
  admin_username      = "adminuser"
  admin_password      = "YourSecurePassword123!"
  network_interface_ids = [azurerm_network_interface.vm_nic.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-Datacenter"
    version   = "latest"
  }
}

resource "azurerm_virtual_machine_extension" "install_confluent" {
  name                 = "InstallConfluentCLI"
  virtual_machine_id   = azurerm_windows_virtual_machine.vm.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  settings = <<JSON
{
  "commandToExecute": "powershell -ExecutionPolicy Unrestricted -Command \"try { $installPath='C:\\\\Windows\\\\Temp\\\\ConfluentCLI'; $extractRoot='C:\\\\Windows\\\\Temp\\\\confluent-cli'; $zipPath='C:\\\\Windows\\\\Temp\\\\confluent-cli.zip'; if(Test-Path $extractRoot){Remove-Item $extractRoot -Recurse -Force}; if(Test-Path $installPath){Remove-Item $installPath -Recurse -Force}; $release=Invoke-RestMethod -Uri 'https://api.github.com/repos/confluentinc/cli/releases/latest'; $asset=$release.assets | Where-Object { $_.name -match 'windows_amd64.zip' } | Select-Object -First 1; Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath; Expand-Archive -Path $zipPath -DestinationPath $extractRoot -Force; $sourcePath=Join-Path $extractRoot 'confluent'; Move-Item -Path $sourcePath -Destination $installPath; Copy-Item -Path (Join-Path $installPath 'confluent.exe') -Destination 'C:\\\\Windows\\\\System32\\\\confluent.exe' -Force; & 'C:\\\\Windows\\\\System32\\\\confluent.exe' --version } catch { Write-Output 'Confluent CLI installation failed: '+$_.Exception.Message }\""
}
JSON
}








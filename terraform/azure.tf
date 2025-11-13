
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
 

# Associate Network Security Group to the network interface
 

 

 

#
# NGINX Proxy (Linux) to mirror AWS setup
#

resource "azurerm_public_ip" "nginx_public_ip" {
  name                = "${var.prefix}-nginx-public-ip"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_security_group" "nginx_nsg" {
  name                = "${var.prefix}-nginx-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "SSH"
    priority                   = 1101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "HTTP"
    priority                   = 1102
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
    priority                   = 1103
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "KAFKA"
    priority                   = 1104
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "9092"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "nginx_nic" {
  name                = "${var.prefix}-nginx-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.public.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.nginx_public_ip.id
  }
}

resource "azurerm_network_interface_security_group_association" "nginx_nic_nsg" {
  network_interface_id      = azurerm_network_interface.nginx_nic.id
  network_security_group_id = azurerm_network_security_group.nginx_nsg.id
}

resource "azurerm_linux_virtual_machine" "nginx_proxy" {
  name                            = "${var.prefix}-nginx-proxy"
  resource_group_name             = azurerm_resource_group.rg.name
  location                        = azurerm_resource_group.rg.location
  size                            = "Standard_B2ms"
  admin_username                  = "azureuser"
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.nginx_nic.id]

  admin_ssh_key {
    username   = "azureuser"
    public_key = tls_private_key.rsa-4096-example.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  custom_data = base64encode(<<EOF
  #cloud-config
  package_update: true
  packages:
    - nginx
    - net-tools
  write_files:
    - path: /etc/nginx/nginx.conf
      permissions: '0644'
      content: |
        user www-data;
        worker_processes auto;
        pid /run/nginx.pid;
        include /etc/nginx/modules-enabled/*.conf;
        events {}
        stream {
          map $ssl_preread_server_name $targetBackend {
             default $ssl_preread_server_name;
          }
          server {
            listen 9092;
            proxy_connect_timeout 1s;
            proxy_timeout 7200s;
            resolver 168.63.129.16 valid=30s ipv6=off;
            proxy_pass $targetBackend:9092;
            ssl_preread on;
          }
          server {
            listen 443;
            proxy_connect_timeout 1s;
            proxy_timeout 7200s;
            resolver 168.63.129.16 valid=30s ipv6=off;
            proxy_pass $targetBackend:443;
            ssl_preread on;
          }
          log_format stream_routing '[$time_local] remote address $remote_addr with SNI name "$ssl_preread_server_name" proxied to "$upstream_addr" $protocol $status $bytes_sent $bytes_received $session_time';
          access_log /var/log/nginx/stream-access.log stream_routing;
        }
        http {
          sendfile on;
          tcp_nopush on;
          types_hash_max_size 2048;
          include /etc/nginx/mime.types;
          default_type application/octet-stream;
          access_log /var/log/nginx/access.log;
          error_log /var/log/nginx/error.log;
          server {
            listen 80 default_server;
            server_name _;
            location /health {
              access_log off;
              return 200 "healthy\n";
              add_header Content-Type text/plain;
            }
            location / { return 404; }
          }
        }
  runcmd:
    - [ bash, -lc, "nginx -t" ]
    - [ systemctl, restart, nginx ]
    - [ systemctl, enable, nginx ]
EOF
  )

  tags = {
    Name = "${var.prefix}-nginx-proxy-${random_id.env_display_id.hex}"
  }
}

# output "update_hosts_macos_linux_azure" {
#   description = "Mac/Linux: Copy and run this command (appends to /etc/hosts) for Azure"
#   value       = "echo '${azurerm_public_ip.nginx_public_ip.ip_address} ${trimsuffix(replace(confluent_kafka_cluster.destcluster.rest_endpoint, "https://", ""), ":443")}' | sudo tee -a /etc/hosts"
# }
#
# output "update_hosts_windows_azure" {
#   description = "Windows: Copy and run this command in CMD as Administrator (appends to hosts file) for Azure"
#   value       = "echo ${azurerm_public_ip.nginx_public_ip.ip_address} ${trimsuffix(replace(confluent_kafka_cluster.destcluster.rest_endpoint, "https://", ""), ":443")} >> C:\\Windows\\System32\\drivers\\etc\\hosts"
# }





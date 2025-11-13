data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}


# ------------------------------------------------------
# VPC
# ------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = {
    Name = "${var.prefix}-vpc-${random_id.env_display_id.hex}"
  }
}

# ------------------------------------------------------
# Public SUBNETS
# ------------------------------------------------------

resource "aws_subnet" "public_subnets" {
  count                   = 3
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index + 1}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name = "${var.prefix}-public-${count.index}-${random_id.env_display_id.hex}"
  }
}

# ------------------------------------------------------
# Private SUBNETS
# ------------------------------------------------------

resource "aws_subnet" "private_subnets" {
  count                   = 3
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index + 10}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false
  tags = {
    Name = "${var.prefix}-private-${count.index}-${random_id.env_display_id.hex}"
  }
}

# ------------------------------------------------------
# IGW
# ------------------------------------------------------
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "${var.prefix}-igw-${random_id.env_display_id.hex}"
  }
}

# ------------------------------------------------------
# EIP
# ------------------------------------------------------

resource "aws_eip" "eip" {
  domain = "vpc"
}

# ------------------------------------------------------
# NAT
# ------------------------------------------------------

resource "aws_nat_gateway" "natgw" {
  allocation_id = aws_eip.eip.id
  subnet_id     = aws_subnet.public_subnets[1].id
  tags = {
    Name = "natgw-${random_id.env_display_id.hex}"
  }
}


# ------------------------------------------------------
# ROUTE TABLE
# ------------------------------------------------------
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "${var.prefix}-public-${random_id.env_display_id.hex}"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.natgw.id
  }
  tags = {
    Name = "${var.prefix}-private-${random_id.env_display_id.hex}"
  }
}

resource "aws_route_table_association" "pub_subnet_associations" {
  count          = 3
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "pri_subnet_associations" {
  count          = 3
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_route_table.id
}

# ------------------------------------------------------
# Security Group for PrivateLink Endpoint
# ------------------------------------------------------

resource "aws_security_group" "sg" {
  name        = "${var.prefix}-sg-${random_id.env_display_id.hex}"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  ingress {
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_tls"
  }
}

# ------------------------------------------------------
# Security Group for NGINX Proxy
# ------------------------------------------------------

resource "aws_security_group" "nginx_sg" {
  name        = "${var.prefix}-nginx-sg-${random_id.env_display_id.hex}"
  description = "Security group for NGINX proxy server"
  vpc_id      = aws_vpc.main.id

  # Allow SSH for management
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Consider restricting this to your IP
    description = "SSH access"
  }

  # Allow HTTPS traffic from anywhere
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS for Kafka REST API"
  }

  # Allow Kafka broker traffic from anywhere
  ingress {
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Kafka broker traffic"
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = {
    Name = "${var.prefix}-nginx-sg-${random_id.env_display_id.hex}"
  }
}

# ------------------------------------------------------
# Get Latest Ubuntu AMI
# ------------------------------------------------------

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical - works in all AWS regions

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# ------------------------------------------------------
# NGINX Proxy EC2 Instance
# ------------------------------------------------------

resource "aws_instance" "nginx_proxy" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.small"
  key_name               = aws_key_pair.tf_key.key_name
  vpc_security_group_ids = [aws_security_group.nginx_sg.id]
  subnet_id              = aws_subnet.public_subnets[0].id

  user_data = <<-EOF
#!/bin/bash
set -e

# Log all output
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "Starting NGINX proxy setup..."

# Update system
apt-get update
apt-get upgrade -y

# Install NGINX
apt-get install -y nginx net-tools

# Backup original config
cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup

# Create NGINX configuration for SNI-based routing
# Note: stream module is already loaded via /etc/nginx/modules-enabled/
cat > /etc/nginx/nginx.conf <<'NGINXCONF'
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
    resolver 169.254.169.253;
    proxy_pass $targetBackend:9092;
    ssl_preread on;
  }
  
  server {
    listen 443;
    proxy_connect_timeout 1s;
    proxy_timeout 7200s;
    resolver 169.254.169.253;
    proxy_pass $targetBackend:443;
    ssl_preread on;
  }
  
  log_format stream_routing '[$time_local] remote address $remote_addr'
                     'with SNI name "$ssl_preread_server_name" '
                     'proxied to "$upstream_addr" '
                     '$protocol $status $bytes_sent $bytes_received '
                     '$session_time';
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

        location / {
            return 404;
        }
    }
}
NGINXCONF

# Test NGINX configuration
nginx -t

# Restart NGINX to apply changes
systemctl restart nginx

# Enable NGINX to start on boot
systemctl enable nginx

# Verify NGINX is running
systemctl status nginx

echo "NGINX proxy setup completed successfully!"

# Display version and status
nginx -v
echo "Resolver configured: 169.254.169.253"

# Show listening ports
netstat -tulpn | grep nginx
EOF

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = {
    Name = "${var.prefix}-nginx-proxy-${random_id.env_display_id.hex}"
  }

  # Ensure the instance is recreated if user_data changes
  user_data_replace_on_change = true
}

# ------------------------------------------------------
# SSH Key Pair
# ------------------------------------------------------

resource "aws_key_pair" "tf_key" {
  key_name   = "${var.prefix}-key-${random_id.env_display_id.hex}"
  public_key = tls_private_key.rsa-4096-example.public_key_openssh
}

resource "tls_private_key" "rsa-4096-example" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "tf_key" {
  content         = tls_private_key.rsa-4096-example.private_key_pem
  filename        = "${path.module}/sshkey-${aws_key_pair.tf_key.key_name}"
  file_permission = "0400"
}

# ------------------------------------------------------
# VPC Endpoint for PrivateLink
# ------------------------------------------------------

resource "aws_vpc_endpoint" "privatelink" {
  vpc_id            = aws_vpc.main.id
  service_name      = confluent_private_link_attachment.sourcepla.aws[0].vpc_endpoint_service_name
  vpc_endpoint_type = "Interface"

  security_group_ids = [
    aws_security_group.sg.id,
  ]

  subnet_ids = aws_subnet.private_subnets[*].id

  private_dns_enabled = false

  tags = {
    Name = "${var.prefix}-confluent-private-link-endpoint-${random_id.env_display_id.hex}"
  }
}

# ------------------------------------------------------
# Route53 Private Hosted Zone
# ------------------------------------------------------

resource "aws_route53_zone" "privatelink" {
  name = confluent_private_link_attachment.sourcepla.dns_domain

  vpc {
    vpc_id = aws_vpc.main.id
  }
}

resource "aws_route53_record" "privatelink" {
  zone_id = aws_route53_zone.privatelink.zone_id
  name    = "*.${aws_route53_zone.privatelink.name}"
  type    = "CNAME"
  ttl     = "60"
  records = [
    aws_vpc_endpoint.privatelink.dns_entry[0]["dns_name"]
  ]
}

# ------------------------------------------------------
# Outputs
# ------------------------------------------------------

# output "update_hosts_macos_linux" {
#   description = "Mac/Linux: Copy and run this command (appends to /etc/hosts)"
#   value       = "echo '${aws_instance.nginx_proxy.public_ip} ${trimsuffix(replace(confluent_kafka_cluster.sourcecluster.rest_endpoint, "https://", ""), ":443")}' | sudo tee -a /etc/hosts"
# }
#
# output "update_hosts_windows" {
#   description = "Windows: Copy and run this command in CMD as Administrator (appends to hosts file)"
#   value       = "echo ${aws_instance.nginx_proxy.public_ip} ${trimsuffix(replace(confluent_kafka_cluster.sourcecluster.rest_endpoint, "https://", ""), ":443")} >> C:\\Windows\\System32\\drivers\\etc\\hosts"
# }

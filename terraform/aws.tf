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
# Security Group
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

# Security Group for Windows EC2 Instance
resource "aws_security_group" "windows_sg" {
  name        = "${var.prefix}-windows-sg-${random_id.env_display_id.hex}"
  description = "Allow RDP traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.prefix}-windows-sg-${random_id.env_display_id.hex}"
  }
}

# ------------------------------------------------------
# Windows EC2 Instance
# ------------------------------------------------------

data "aws_ami" "windows" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2025-English-Full-Base-*"]
  }
}

resource "aws_instance" "windows_instance" {
  ami                    = data.aws_ami.windows.image_id
  instance_type          = "t3.large"
  key_name               = aws_key_pair.tf_key.key_name
  vpc_security_group_ids = [aws_security_group.windows_sg.id]
  subnet_id              = aws_subnet.public_subnets[0].id
  get_password_data      = true

  user_data_base64 = base64encode(<<-EOF
    <powershell>
    # Wait for the system to be fully ready
    Start-Sleep -Seconds 60
    Start-Transcript -Path "C:\\Windows\\Temp\\confluent-install.log" -Force

    try {
        $installPath = "C:\\Windows\\Temp\\ConfluentCLI"
        $extractRoot = "C:\\Windows\\Temp\\confluent-cli"
        $zipPath = "C:\\Windows\\Temp\\confluent-cli.zip"

        # Cleanup old directories
        if (Test-Path $extractRoot) { Remove-Item $extractRoot -Recurse -Force }
        if (Test-Path $installPath) { Remove-Item $installPath -Recurse -Force }

        # Download latest Confluent CLI release
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/confluentinc/cli/releases/latest"
        $asset = $release.assets | Where-Object { $_.name -match "windows_amd64.zip" } | Select-Object -First 1
        if (-not $asset) { throw "Could not find windows_amd64.zip asset" }

        Write-Output "Downloading Confluent CLI from $($asset.browser_download_url)"
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath

        Write-Output "Extracting to $extractRoot"
        Expand-Archive -Path $zipPath -DestinationPath $extractRoot -Force

        # Move inner 'confluent' folder to install path
        $sourcePath = Join-Path $extractRoot "confluent"
        if (-not (Test-Path $sourcePath)) { throw "Expected 'confluent' folder not found" }
        Move-Item -Path $sourcePath -Destination $installPath

        # Move confluent.exe into C:\Windows\System32 so it's globally available
        $exeSource = Join-Path $installPath "confluent.exe"
        $exeTarget = "C:\\Windows\\System32\\confluent.exe"
        if (Test-Path $exeSource) {
            Copy-Item -Path $exeSource -Destination $exeTarget -Force
        } else {
            throw "confluent.exe not found at $exeSource"
        }

        # Verify installation
        $version = & $exeTarget --version
        Write-Output "Confluent CLI version installed: $version"

    } catch {
        Write-Output "Confluent CLI installation failed: $($_.Exception.Message)"
    }

    Stop-Transcript
    </powershell>
    EOF
  )

  root_block_device {
    volume_size = 30
  }

  tags = {
    Name = "${var.prefix}-windows-instance-${random_id.env_display_id.hex}"
  }
}


resource "aws_key_pair" "tf_key" {
  key_name   = "${var.prefix}-key-${random_id.env_display_id.hex}"
  public_key = tls_private_key.rsa-4096-example.public_key_openssh
}

# RSA key of size 4096 bits
resource "tls_private_key" "rsa-4096-example" {
  algorithm = "RSA"
  rsa_bits  = 4096

}

resource "local_file" "tf_key" {
  content  = tls_private_key.rsa-4096-example.private_key_pem
  filename = "${path.module}/sshkey-${aws_key_pair.tf_key.key_name}"
  file_permission = "0400"
}


# ------------------------------------------------------
# VPC Endpoint
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


# # ------------------------------------------------------
# VPC Endpoint
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
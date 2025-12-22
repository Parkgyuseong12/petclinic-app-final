# =============================================================================
# VPC Module
# 고가용성(HA)을 위한 2-Tier Architecture with Zonal Isolation
# =============================================================================

# -----------------------------------------------------------------------------
# VPC
# -----------------------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = var.vpc_tags
}

# -----------------------------------------------------------------------------
# Internet Gateway
# -----------------------------------------------------------------------------
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = var.igw_tags
}

# -----------------------------------------------------------------------------
# Public Subnets (2개 - 각 AZ별 1개)
# 용도: Bastion Host, NAT Gateway, ALB
# -----------------------------------------------------------------------------
resource "aws_subnet" "public" {
  count = length(var.availability_zones)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(
    var.public_subnet_tags,
    {
      Name = "${var.name_prefix}-public-subnet-${count.index + 1}"
    }
  )
}

# -----------------------------------------------------------------------------
# App Private Subnets (2개 - 각 AZ별 1개)
# 용도: Management Server, EKS Nodes, Application Pods
# -----------------------------------------------------------------------------
resource "aws_subnet" "private_app" {
  count = length(var.availability_zones)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.app_private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(
    var.app_private_subnet_tags,
    {
      Name = "${var.name_prefix}-private-app-subnet-${count.index + 1}"
    }
  )
}

# -----------------------------------------------------------------------------
# DB Private Subnets (2개 - 각 AZ별 1개)
# 용도: RDS, Database
# -----------------------------------------------------------------------------
resource "aws_subnet" "private_db" {
  count = length(var.availability_zones)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.db_private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(
    var.db_private_subnet_tags,
    {
      Name = "${var.name_prefix}-private-db-subnet-${count.index + 1}"
    }
  )
}

# -----------------------------------------------------------------------------
# 자동 확장 nat
# -----------------------------------------------------------------------------
resource "aws_nat_gateway" "main" {
  # count 제거 (단일 리소스)
  
  vpc_id            = aws_vpc.main.id
  availability_mode = "regional"

  tags = merge(
    var.nat_gateway_tags,
    {
      Name = "${var.name_prefix}-nat-gw-regional"
    }
  )

  depends_on = [aws_internet_gateway.main]
}

# -----------------------------------------------------------------------------
# Public Route Table (1개 - 모든 Public Subnet 공유)
# -----------------------------------------------------------------------------
# Public RT
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags = merge(
    var.public_rt_tags,
    { Name = "${var.name_prefix}-public-rt" }
  )
}
# -----------------------------------------------------------------------------
# App Private Route Tables (2개 - 각 AZ별 1개, Zonal Isolation)
# -----------------------------------------------------------------------------
resource "aws_route_table" "private_app" {
  count  = length(var.availability_zones)
  vpc_id = aws_vpc.main.id
  tags = merge(
    var.app_private_rt_tags,
    {
      Name = "${var.name_prefix}-private-app-rt-${count.index + 1}"
      AZ   = var.availability_zones[count.index]
    }
  )
}

# -----------------------------------------------------------------------------
# DB Private Route Tables (2개 - 각 AZ별 1개, Zonal Isolation)
# DB Private Subnet은 NAT Gateway를 사용하지 않음 (인터넷 접근 불필요)
# 또는 필요시 NAT Gateway 사용 가능
# -----------------------------------------------------------------------------
resource "aws_route_table" "private_db" {
  count  = length(var.availability_zones)
  vpc_id = aws_vpc.main.id
  tags = merge(
    var.db_private_rt_tags,
    {
      Name = "${var.name_prefix}-private-db-rt-${count.index + 1}"
      AZ   = var.availability_zones[count.index]
    }
  )
}

# Public Subnet -> IGW
resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

# App Private Subnet -> Regional NAT Gateway
# * 변경점: 모든 Private RT가 하나의 Regional NAT Gateway ID를 바라봄
resource "aws_route" "private_app_nat" {
  count                  = length(var.availability_zones)
  route_table_id         = aws_route_table.private_app[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main.id # Index 불필요 (단일 ID)
}

# DB Private Subnet -> Regional NAT Gateway (Optional)
resource "aws_route" "private_db_nat" {
  count                  = length(var.availability_zones)
  route_table_id         = aws_route_table.private_db[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main.id # Index 불필요
}

# -----------------------------------------------------------------------------
# 6. Route Table Associations
# -----------------------------------------------------------------------------
resource "aws_route_table_association" "public" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private_app" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.private_app[count.index].id
  route_table_id = aws_route_table.private_app[count.index].id
}

resource "aws_route_table_association" "private_db" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.private_db[count.index].id
  route_table_id = aws_route_table.private_db[count.index].id
}

# =============================================================================
# [ADDITIONAL] VPN Configuration (AWS <-> Azure)
# =============================================================================

# 1. VPN Gateway & Attachment
resource "aws_vpn_gateway" "main" {
  tags = { Name = "${var.name_prefix}-vpn-gw" }
}

resource "aws_vpn_gateway_attachment" "vpn_attachment" {
  vpc_id         = aws_vpc.main.id
  vpn_gateway_id = aws_vpn_gateway.main.id
}

# 2. Customer Gateway (Azure Side)
resource "aws_customer_gateway" "main" {
  bgp_asn    = var.azure_bgp_asn
  ip_address = var.azure_public_ip
  type       = "ipsec.1"

  tags = { Name = "${var.name_prefix}-cgw-azure" }
}

# 3. VPN Connection
resource "aws_vpn_connection" "main" {
  vpn_gateway_id      = aws_vpn_gateway.main.id
  customer_gateway_id = aws_customer_gateway.main.id
  type                = "ipsec.1"
  static_routes_only  = true

  tags = { Name = "${var.name_prefix}-vpn-conn-azure" }
}

# 4. VPN Connection Route
resource "aws_vpn_connection_route" "azure" {
  destination_cidr_block = var.azure_cidr
  vpn_connection_id      = aws_vpn_connection.main.id
}

# 5. VPC Route Propagation (Static Routes to Azure)

# Public RT -> VPN
resource "aws_route" "vpn_access_public" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = var.azure_cidr
  gateway_id             = aws_vpn_gateway.main.id
  depends_on             = [aws_vpn_gateway_attachment.vpn_attachment]
}

# App Private RTs -> VPN
resource "aws_route" "vpn_access_app" {
  count                  = length(var.availability_zones)
  route_table_id         = aws_route_table.private_app[count.index].id
  destination_cidr_block = var.azure_cidr
  gateway_id             = aws_vpn_gateway.main.id
  depends_on             = [aws_vpn_gateway_attachment.vpn_attachment]
}

# DB Private RTs -> VPN
resource "aws_route" "vpn_access_db" {
  count                  = length(var.availability_zones)
  route_table_id         = aws_route_table.private_db[count.index].id
  destination_cidr_block = var.azure_cidr
  gateway_id             = aws_vpn_gateway.main.id
  depends_on             = [aws_vpn_gateway_attachment.vpn_attachment]
}

# =============================================================================
# [ADDITIONAL] Route 53 Resolver (for Azure Private DNS)
# =============================================================================

# 1. Resolver Security Group
resource "aws_security_group" "dns_resolver_sg" {
  name        = "${var.name_prefix}-dns-resolver-sg"
  description = "Allow DNS outbound traffic to Azure"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 2. Outbound Endpoint
resource "aws_route53_resolver_endpoint" "outbound" {
  name      = "${var.name_prefix}-dns-outbound-endpoint"
  direction = "OUTBOUND"

  security_group_ids = [aws_security_group.dns_resolver_sg.id]

  # HA 구성을 위해 각 AZ의 DB 서브넷에 ENI 생성
  dynamic "ip_address" {
    for_each = aws_subnet.private_db
    content {
      subnet_id = ip_address.value.id
    }
  }
}

# 3. Resolver Rule (Forward to Azure DNS)
resource "aws_route53_resolver_rule" "azure_mysql_rule" {
  name                 = "${var.name_prefix}-forward-azure-mysql"
  domain_name          = "mysql.database.azure.com"
  rule_type            = "FORWARD"
  resolver_endpoint_id = aws_route53_resolver_endpoint.outbound.id

  target_ip {
    ip = var.azure_dns_ip
  }
}

# 4. Rule Association
resource "aws_route53_resolver_rule_association" "azure_mysql_assoc" {
  resolver_rule_id = aws_route53_resolver_rule.azure_mysql_rule.id
  vpc_id           = aws_vpc.main.id
}

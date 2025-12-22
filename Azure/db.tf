# # 1. DB 접속 비밀번호 자동 생성 (보안을 위해 랜덤 생성)
# resource "random_password" "db_password" {
#   length           = 16
#   special          = true
#   override_special = "!#$%&*()-_=+[]{}<>:?"
# }

# 서버 이름 중복 방지용 랜덤 접미사 (소문자 + 숫자)
resource "random_string" "server_suffix" {
  length  = 8
  special = false
  upper   = false
  numeric = true
}

# 2. Private DNS Zone (VNet 통합을 위해 필수)
resource "azurerm_private_dns_zone" "dns_zone" {
  name                = "bespin.mysql.database.azure.com"
  resource_group_name = azurerm_resource_group.rg.name
}

# 3. Private DNS와 VNet 연결
resource "azurerm_private_dns_zone_virtual_network_link" "dns_link" {
  name                  = "bespin-dns-link"
  private_dns_zone_name = azurerm_private_dns_zone.dns_zone.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
  resource_group_name   = azurerm_resource_group.rg.name
}

# 4. DB용 네트워크 보안 그룹 (NSG) - 3306 포트 허용
resource "azurerm_network_security_group" "db_nsg" {
  name                = "db-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "AllowMySQL"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3306"
    source_address_prefix      = "192.168.0.0/16" # VNet 내부에서만 접근 가능하도록 설정
    destination_address_prefix = "*"
  }
  security_rule {
    name                       = "AllowAwsMySQL"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3306"
    source_address_prefix      = var.aws_vpc_cidr # aws vpc 내부에서만 접근 가능하도록 설정
    destination_address_prefix = "*"
  }
}

# 5. DB 서브넷에 NSG 연결
resource "azurerm_subnet_network_security_group_association" "db_nsg_assoc" {
  subnet_id                 = azurerm_subnet.db_subnet.id
  network_security_group_id = azurerm_network_security_group.db_nsg.id
}

# 6. Azure Database for MySQL Flexible Server 생성
resource "azurerm_mysql_flexible_server" "mysql" {
  name                   = "mysql-${random_string.server_suffix.result}"
  resource_group_name    = azurerm_resource_group.rg.name
  location               = azurerm_resource_group.rg.location
  administrator_login    = var.db_admin_username
  administrator_password = var.db_admin_password
  sku_name               = "B_Standard_B1ms"

  # ★ 핵심 변경 사항: AWS RDS(8.0)와 버전을 맞춤
  version = "8.0.21"

  # 중요: VNet 통합 설정
  delegated_subnet_id = azurerm_subnet.db_subnet.id
  private_dns_zone_id = azurerm_private_dns_zone.dns_zone.id

  # DNS 연결이 먼저 되어야 함
  depends_on = [azurerm_private_dns_zone_virtual_network_link.dns_link]
}

# 6-1. Azure Database 설정값 변경
resource "azurerm_mysql_flexible_server_configuration" "no_ssl" {
  #네임값이 중요하다. 실제 옵션을 이 네임으로 지정하는 듯?
  name                = "require_secure_transport"
  resource_group_name = azurerm_resource_group.rg.name
  server_name         = azurerm_mysql_flexible_server.mysql.name
  value               = "OFF"
}

# 7. 실제 데이터베이스 생성 (Schema)
resource "azurerm_mysql_flexible_database" "database" {
  name                = "bespindb"
  resource_group_name = azurerm_resource_group.rg.name
  server_name         = azurerm_mysql_flexible_server.mysql.name
  charset             = "utf8mb4"
  collation           = "utf8mb4_unicode_ci"
}

###
# myloader를 사용한 rds 덤프를 위한 gtid 설정
# Azure Database 설정값 변경
resource "azurerm_mysql_flexible_server_configuration" "gtid" {
  #네임값이 중요하다. 실제 옵션을 이 네임으로 지정하는 듯?
  name                = "gtid_mode"
  resource_group_name = azurerm_resource_group.rg.name
  server_name         = azurerm_mysql_flexible_server.mysql.name
  value               = "ON"
}

resource "azurerm_mysql_flexible_server_configuration" "gtid_enforce" {
  #네임값이 중요하다. 실제 옵션을 이 네임으로 지정하는 듯?
  name                = "enforce_gtid_consistency"
  resource_group_name = azurerm_resource_group.rg.name
  server_name         = azurerm_mysql_flexible_server.mysql.name
  value               = "ON"
}

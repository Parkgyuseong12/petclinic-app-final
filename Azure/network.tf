
# 1. 리소스 그룹: 모든 리소스를 묶어서 관리하는 논리적 컨테이너
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

# 2. 가상 네트워크 (VNet): 사설 네트워크 공간 정의
resource "azurerm_virtual_network" "vnet" {
  name                = "${var.vm_name}-vnet"
  address_space       = ["192.168.0.0/16"] # aws와 다르게
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# 3. 서브넷: VNet을 더 작게 쪼갠 단위 (실제 VM이 배치되는 곳)
resource "azurerm_subnet" "subnet" {
  name                 = "default"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["192.168.1.0/24"] # 10.0.1.x 대역 사용

}

# MySQL Flexible Server 전용 서브넷 (Delegation 필수)
resource "azurerm_subnet" "db_subnet" {
  name                 = "db-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["192.168.2.0/24"]
  service_endpoints    = ["Microsoft.Storage"]

  delegation {
    name = "fs"
    service_delegation {
      name = "Microsoft.DBforMySQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

# 4. 공인 IP (Public IP): 외부에서 인터넷을 통해 접속하기 위한 IP
resource "azurerm_public_ip" "pip" {
  name                = "${var.vm_name}-pip"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  # Static: IP가 변하지 않음 (서버용으로 적합)
  # Dynamic: VM 재부팅 시 IP가 변경될 수 있음
  # Standard SKU는 반드시 Static
  allocation_method = "Static"
  #기본값
  #sku                 = "Standard" # Availability Zone 등을 지원하는 표준 SKU
}

# ---------------------------------------------------------
# [추가] DNS 관련 리소스
# ---------------------------------------------------------

# DnsResolvers 전용 서브넷
resource "azurerm_subnet" "dns_subnet" {
  name                 = "DNSSubnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["192.168.200.0/24"]
  delegation {
    name = "dns-resolver-delegation"

    service_delegation {
      name    = "Microsoft.Network/dnsResolvers" # 위임할 서비스 명시
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_private_dns_resolver" "azure_private_resolver" {
  name                = "Azure_Private_Resolver"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  virtual_network_id  = azurerm_virtual_network.vnet.id
  depends_on = [
    azurerm_mysql_flexible_server.mysql
  ]
}

resource "azurerm_private_dns_resolver_inbound_endpoint" "dns_inbound" {
  name                    = "dns_inbound"
  private_dns_resolver_id = azurerm_private_dns_resolver.azure_private_resolver.id
  location                = azurerm_private_dns_resolver.azure_private_resolver.location
  ip_configurations {
    private_ip_allocation_method = "Dynamic"
    subnet_id                    = azurerm_subnet.dns_subnet.id
  }
}

# ---------------------------------------------------------
# [추가] VPN Gateway 관련 리소스
# ---------------------------------------------------------

# 6. Gateway 전용 서브넷 (이름은 반드시 GatewaySubnet 이어야 함)
resource "azurerm_subnet" "gateway_subnet" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["192.168.255.0/24"]
}

# 7. VPN Gateway용 공인 IP
resource "azurerm_public_ip" "vpn_pip" {
  name                = "vpn-gateway-pip"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Standard"
  allocation_method   = "Static"
}

# 8. Virtual Network Gateway (VPN Gateway 본체)
resource "azurerm_virtual_network_gateway" "vpn_gateway" {
  name                = "migration-vpn-gateway"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  #암호화 설정
  type     = "Vpn"
  vpn_type = "RouteBased"

  active_active = false
  enable_bgp    = false
  sku           = "VpnGw1" # 실습용으로 적절 (Basic은 제약이 많음)
  generation    = "Generation1"

  ip_configuration {
    name                          = "vnetGatewayConfig"
    public_ip_address_id          = azurerm_public_ip.vpn_pip.id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.gateway_subnet.id
  }
}
# ---------------------------------------------------------
# vpn connection
# ---------------------------------------------------------
# AWS 완료 후 주석 풀고 값 넣고 실행
# 1. Local Network Gateway (AWS의 정보를 Azure에 등록)
resource "azurerm_local_network_gateway" "aws_lng" {
  name                = "aws-local-gateway"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  # AWS VPN 터널의 외부 IP (3.x.x.x 등)
  gateway_address = var.aws_vpn_public_ip

  # AWS VPC 내부 CIDR (10.0.0.0/16 등) - 라우팅을 위해 필수
  address_space = [var.aws_vpc_cidr]
}

# 2. Connection (Azure Gateway와 AWS Gateway를 연결)
resource "azurerm_virtual_network_gateway_connection" "azure_to_aws" {
  name                = "azure-to-aws-connection"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  type                       = "IPsec"
  virtual_network_gateway_id = azurerm_virtual_network_gateway.vpn_gateway.id
  local_network_gateway_id   = azurerm_local_network_gateway.aws_lng.id

  # AWS에서 설정한 Pre-Shared Key와 동일해야 함
  shared_key = var.vpn_shared_key
}
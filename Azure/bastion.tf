# -------------------------------------------------------------------
# 컴퓨팅 리소스 (VM) 구성
# 실제 서버와 랜카드(NIC)를 생성합니다.
# -------------------------------------------------------------------

# 0. 네트워크 보안 그룹 (NSG): 가상 방화벽 역할
resource "azurerm_network_security_group" "nsg" {
  name                = "${var.vm_name}-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  # SSH 접속 허용 규칙 (포트 22)
  security_rule {
    name                       = "SSH"
    priority                   = 1001      # 우선순위 (낮을수록 먼저 적용됨)
    direction                  = "Inbound" # 들어오는 트래픽
    access                     = "Allow"   # 허용
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22" # 목적지 포트 (SSH)
    source_address_prefix      = "*"  # 모든 출발지 IP 허용 (보안상 특정 IP로 제한하는 것이 좋음)
    destination_address_prefix = "*"
  }

  # AWS에서 들어오는 Ping(ICMP) 및 모든 트래픽 허용
  security_rule {
    name                       = "AllowAWSInbound"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*" # TCP, UDP, ICMP 모두 허용
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = var.aws_vpc_cidr # AWS VPC 대역 (예: 10.0.0.0/16)
    destination_address_prefix = "*"
  }
}

# 1. 네트워크 인터페이스 (NIC): 가상 랜카드
resource "azurerm_network_interface" "nic" {
  name                = "${var.vm_name}-nic"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }
}

# 2. NIC와 NSG 연결: 랜카드에 방화벽 규칙 적용
resource "azurerm_network_interface_security_group_association" "nic_nsg" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# 3. 리눅스 가상 머신 생성
resource "azurerm_linux_virtual_machine" "vm" {
  name                = var.vm_name
  resource_group_name = var.resource_group_name
  location            = var.location
  size                = "Standard_B1s" # VM 크기 (CPU, RAM 사양)
  admin_username      = var.admin_username

  # 위에서 만든 NIC 연결
  network_interface_ids = [
    azurerm_network_interface.nic.id,
  ]

  # SSH 키 설정 (비밀번호 방식보다 보안 우수)
  admin_ssh_key {
    username = var.admin_username
    # file() 함수: 로컬 경로에 있는 파일의 내용을 텍스트로 읽어옵니다.
    public_key = file(var.ssh_public_key_path)
  }

  # OS 디스크 설정
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS" # 표준 HDD/SSD (비용 절감)
  }

  # 운영체제 이미지 정보 (Ubuntu 22.04 LTS)
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  user_data = base64encode(templatefile("userdata.tftpl", {
    db_host     = azurerm_mysql_flexible_server.mysql.fqdn
    db_admin    = azurerm_mysql_flexible_server.mysql.administrator_login
    db_password = azurerm_mysql_flexible_server.mysql.administrator_password
  }))
  depends_on = [
    azurerm_mysql_flexible_server.mysql,
    azurerm_network_security_group.nsg # 방화벽 규칙이 있다면 이것도 포함
  ]
}
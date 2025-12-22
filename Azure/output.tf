/* output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "public_ip_address" {
  value = azurerm_public_ip.pip.ip_address
} */

# 접속 편의를 위해 개인키 경로를 절대 경로로 조합하여 출력합니다.
output "ssh_command" {
  value = "ssh -i /home/ubuntu/task/BespinFinal/keys/mykey ${var.admin_username}@${azurerm_public_ip.pip.ip_address}"
}

# DB 접속 정보 출력
output "db_connect_command" {
  value = "mysql -h ${azurerm_mysql_flexible_server.mysql.fqdn} -u ${var.db_admin_username} -p'${var.db_admin_password}' "
}

#### aws tfvars입력 정보 ####

# vpn ip
output "azure_public_ip" {
  value = azurerm_public_ip.vpn_pip.ip_address
}
output "azure_dns_inbound_ip" {
  description = "AWS Route 53 Resolver가 쿼리를 보낼 Azure DNS Inbound IP"
  value       = azurerm_private_dns_resolver_inbound_endpoint.dns_inbound.ip_configurations[0].private_ip_address
}

# # 중요: 생성된 DB 비밀번호 출력 (민감 정보이므로 sensitive=true)
# output "mysql_admin_password" {
#   value     = random_password.db_password.result
#   # 이렇게 설정하면 output에서 따로 입력해야 보인다.
#   # 빠른 테스트를 위해 제거
#   #sensitive = true
# }
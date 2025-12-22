# =============================================================================
# VPC Module Outputs
# =============================================================================

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "VPC CIDR Block"
  value       = aws_vpc.main.cidr_block
}

output "igw_id" {
  description = "Internet Gateway ID"
  value       = aws_internet_gateway.main.id
}

output "public_subnet_ids" {
  description = "Public Subnet IDs"
  value       = aws_subnet.public[*].id
}

output "app_private_subnet_ids" {
  description = "App Private Subnet IDs"
  value       = aws_subnet.private_app[*].id
}

output "db_private_subnet_ids" {
  description = "DB Private Subnet IDs"
  value       = aws_subnet.private_db[*].id
}

output "nat_gateway_ids" {
  description = "NAT Gateway IDs"
  value       = aws_nat_gateway.main[*].id
}

output "public_route_table_id" {
  description = "Public Route Table ID"
  value       = aws_route_table.public.id
}

output "app_private_route_table_ids" {
  description = "App Private Route Table IDs"
  value       = aws_route_table.private_app[*].id
}

output "db_private_route_table_ids" {
  description = "DB Private Route Table IDs"
  value       = aws_route_table.private_db[*].id
}

output "vpn_tunnel1_address" {
  description = "VPN Tunnel 1 Public IP"
  value       = aws_vpn_connection.main.tunnel1_address
}

output "vpn_tunnel1_preshared_key" {
  description = "VPN Tunnel 1 Preshared Key"
  value       = aws_vpn_connection.main.tunnel1_preshared_key
  sensitive   = true
}
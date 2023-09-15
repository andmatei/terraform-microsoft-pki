output "url" {
  value       = aws_lb.this.dns_name
  description = "ELB DNS name to connect to RDP Gateway."
}

output "security_group_id" {
  value       = aws_security_group.this.id
  description = "Remote Desktop Gateway security group ID."
}

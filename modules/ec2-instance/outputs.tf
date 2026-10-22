output "instance_id" {
  description = "ID of the EC2 instance."
  value       = aws_instance.this.id
}

output "private_ip" {
  description = "Private IPv4 address of the instance."
  value       = aws_instance.this.private_ip
}

output "ami_id" {
  description = "AMI the instance was launched from."
  value       = aws_instance.this.ami
}

output "availability_zone" {
  description = "Availability Zone of the instance."
  value       = aws_instance.this.availability_zone
}

output "security_group_id" {
  description = "ID of the instance's security group."
  value       = aws_security_group.this.id
}

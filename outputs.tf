output "instance_id" {
  description = "ID of the EC2 instance."
  value       = module.ec2_instance.instance_id
}

output "private_ip" {
  description = "Private IPv4 address of the instance."
  value       = module.ec2_instance.private_ip
}

output "ami_id" {
  description = "AMI the instance was launched from."
  value       = module.ec2_instance.ami_id
}

output "availability_zone" {
  description = "Availability Zone of the instance."
  value       = module.ec2_instance.availability_zone
}

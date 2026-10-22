variable "aws_region" {
  description = "AWS Region to deploy into (for example eu-north-1). Set it as a Terraform variable in the HCP Terraform workspace."
  type        = string
}

variable "instance_name" {
  description = "Name tag of the EC2 instance; also the prefix of its security group name."
  type        = string
  default     = "automation-05-demo"
}

variable "instance_type" {
  description = "EC2 instance type. t3.micro is Free Tier eligible for AWS accounts created before and after 15 July 2025."
  type        = string
  default     = "t3.micro"
}

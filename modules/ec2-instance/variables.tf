variable "name" {
  description = "Name tag of the instance; also the prefix of the security group name."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,62}$", var.name))
    error_message = "The name must be 1-63 characters long and use only lowercase letters, digits and hyphens (not starting with a hyphen)."
  }
}

variable "instance_type" {
  description = "EC2 instance type. Must match the AMI architecture: x86_64 types (for example t3.micro) with the default AMI parameter."
  type        = string
  default     = "t3.micro"
}

variable "ami_ssm_parameter" {
  description = "Public SSM parameter that holds the AMI ID. Default: latest Amazon Linux 2023 for x86_64. For Graviton types (t4g) use .../al2023-ami-kernel-default-arm64."
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

variable "subnet_id" {
  description = "Subnet to launch into. If null, the module picks a default subnet of the default VPC in an Availability Zone that offers instance_type."
  type        = string
  default     = null
}

variable "associate_public_ip_address" {
  description = "Whether to give the instance a public IPv4 address. Default false: nothing needs to reach the instance, and AWS charges for public IPv4 addresses."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Extra tags for the module's resources (merged with the provider's default_tags)."
  type        = map(string)
  default     = {}
}

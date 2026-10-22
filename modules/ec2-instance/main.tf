# ---------------------------------------------------------------------------
# Look-ups (read-only, so they also work with the read-only plan role)
# ---------------------------------------------------------------------------

# Latest AMI ID, published by AWS as a public SSM parameter.
data "aws_ssm_parameter" "ami" {
  name = var.ami_ssm_parameter
}

# Availability Zones in this Region that offer the chosen instance type.
data "aws_ec2_instance_type_offerings" "available" {
  location_type = "availability-zone"

  filter {
    name   = "instance-type"
    values = [var.instance_type]
  }
}

data "aws_vpc" "default" {
  count   = var.subnet_id == null ? 1 : 0
  default = true
}

data "aws_subnets" "default" {
  count = var.subnet_id == null ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default[0].id]
  }

  filter {
    name   = "default-for-az"
    values = ["true"]
  }

  filter {
    name   = "availability-zone"
    values = data.aws_ec2_instance_type_offerings.available.locations
  }
}

locals {
  # The given subnet, or the first matching default subnet (sorted, so the choice is stable).
  subnet_id = var.subnet_id != null ? var.subnet_id : try(sort(data.aws_subnets.default[0].ids)[0], null)
}

data "aws_subnet" "selected" {
  id = local.subnet_id

  lifecycle {
    precondition {
      condition     = local.subnet_id != null
      error_message = "No default subnet found in an Availability Zone that offers ${var.instance_type}. Set subnet_id explicitly."
    }
  }
}

# ---------------------------------------------------------------------------
# Resources
# ---------------------------------------------------------------------------

# No inbound rules at all; outbound allowed.
resource "aws_security_group" "this" {
  name_prefix = "${var.name}-"
  description = "No inbound access, outbound allowed. Managed by Terraform."
  vpc_id      = data.aws_subnet.selected.vpc_id

  tags = merge(var.tags, { Name = var.name })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_egress_rule" "all_ipv4" {
  security_group_id = aws_security_group.this.id
  description       = "Allow all outbound IPv4 traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_instance" "this" {
  ami                         = data.aws_ssm_parameter.ami.insecure_value
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnet.selected.id
  vpc_security_group_ids      = [aws_security_group.this.id]
  associate_public_ip_address = var.associate_public_ip_address

  # IMDSv2 only. AL2023 AMIs already default to this; keep it explicit.
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
  }

  tags = merge(var.tags, { Name = var.name })

  lifecycle {
    # The SSM parameter points to a new AMI with every AL2023 release. Without
    # this, each release would replace the instance. Remove it to roll the AMI.
    ignore_changes = [ami]
  }
}

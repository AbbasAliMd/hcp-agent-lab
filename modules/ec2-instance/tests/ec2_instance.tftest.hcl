# Offline unit tests: no AWS credentials and no HCP Terraform needed.
# Run from modules/ec2-instance:  terraform init && terraform test

mock_provider "aws" {
  mock_data "aws_ssm_parameter" {
    defaults = {
      insecure_value = "ami-0123456789abcdef0"
    }
  }

  mock_data "aws_ec2_instance_type_offerings" {
    defaults = {
      locations = ["eu-north-1a", "eu-north-1b"]
    }
  }

  mock_data "aws_vpc" {
    defaults = {
      id = "vpc-0123456789abcdef0"
    }
  }

  mock_data "aws_subnets" {
    defaults = {
      ids = ["subnet-0bbbbbbbbbbbbbbbb", "subnet-0aaaaaaaaaaaaaaaa"]
    }
  }

  mock_data "aws_subnet" {
    defaults = {
      vpc_id = "vpc-0123456789abcdef0"
    }
  }
}

variables {
  name = "unit-test"
}

run "secure_defaults" {
  command = plan

  assert {
    condition     = aws_instance.this.metadata_options[0].http_tokens == "required"
    error_message = "IMDSv2 must be required."
  }

  assert {
    condition     = aws_instance.this.root_block_device[0].encrypted == true
    error_message = "The root volume must be encrypted."
  }

  assert {
    condition     = aws_instance.this.associate_public_ip_address == false
    error_message = "No public IPv4 address by default."
  }

  assert {
    condition     = aws_instance.this.instance_type == "t3.micro"
    error_message = "The default instance type must be t3.micro."
  }

  assert {
    condition     = aws_instance.this.ami == "ami-0123456789abcdef0"
    error_message = "The AMI must come from the SSM parameter."
  }

  assert {
    condition     = aws_instance.this.subnet_id == "subnet-0aaaaaaaaaaaaaaaa"
    error_message = "The first default subnet (sorted) must be chosen."
  }

  assert {
    condition     = aws_instance.this.tags["Name"] == "unit-test"
    error_message = "The Name tag must equal var.name."
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.all_ipv4.cidr_ipv4 == "0.0.0.0/0"
    error_message = "Outbound IPv4 must be allowed."
  }
}

run "explicit_subnet_skips_default_vpc_lookup" {
  command = plan

  variables {
    subnet_id = "subnet-0cccccccccccccccc"
  }

  assert {
    condition     = aws_instance.this.subnet_id == "subnet-0cccccccccccccccc"
    error_message = "An explicit subnet_id must be used as-is."
  }

  assert {
    condition     = length(data.aws_vpc.default) == 0 && length(data.aws_subnets.default) == 0
    error_message = "The default VPC must not be looked up when subnet_id is set."
  }
}

run "rejects_invalid_name" {
  command = plan

  variables {
    name = "Invalid_Name"
  }

  expect_failures = [var.name]
}

run "fails_without_matching_default_subnet" {
  command = plan

  override_data {
    target = data.aws_subnets.default[0]
    values = {
      ids = []
    }
  }

  expect_failures = [data.aws_subnet.selected]
}

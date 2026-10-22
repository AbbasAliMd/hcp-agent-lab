terraform {
  # Tested with Terraform 1.14.9 and 1.16.6.
  required_version = ">= 1.14.0, < 2.0.0"

  # Connects this configuration to HCP Terraform. State is stored in the
  # workspace, and `terraform plan` on a laptop runs remotely with the
  # workspace's variables and AWS role (dynamic provider credentials).
  cloud {
    organization = "abbas-test"

    workspaces {
      project = "aws-lab"
      name    = "ec2-automation-05"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

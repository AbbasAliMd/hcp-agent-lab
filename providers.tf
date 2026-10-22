# No credentials here on purpose: HCP Terraform injects short-lived AWS
# credentials into every plan and apply (dynamic provider credentials).
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      ManagedBy    = "hcp-terraform"
      HCPWorkspace = "abbas-test/aws-lab/ec2-automation-05"
    }
  }
}

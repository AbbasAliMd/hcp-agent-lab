module "ec2_instance" {
  source = "./modules/ec2-instance"

  name          = var.instance_name
  instance_type = var.instance_type

  tags = {
    Owner = "managed-ec2-single-mode-off"
  }
}

module "ec2_instance_second" {
  source = "./modules/ec2-instance"

  name          = "second-ec2"
  instance_type = var.instance_type

  tags = {
    Owner = "managed-ec2-single-mode-off"
  }
}

module "ec2_instance" {
  source = "./modules/ec2-instance"

  name          = var.instance_name
  instance_type = var.instance_type
}

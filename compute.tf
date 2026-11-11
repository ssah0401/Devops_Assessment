data "aws_ami" "linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-kernel-6.1-x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}
resource "aws_vpc" "assessment" {
  cidr_block           = "10.42.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "assessment", Environment = "assessment", Owner = "devops" }
}
resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.assessment.id
  cidr_block              = "10.42.1.0/24"
  map_public_ip_on_launch = false
  tags                    = { Name = "assessment-private", Environment = "assessment", Owner = "devops" }
}
resource "aws_security_group" "instances" {
  name        = "assessment-instances"
  description = "No ingress or egress; add private management connectivity explicitly if needed"
  vpc_id      = aws_vpc.assessment.id
  tags        = { Name = "assessment-instances", Environment = "assessment", Owner = "devops" }
}
module "ec2" {
  source = "./modules/ec2"
  instances = {
    for name, config in var.instances : name => merge(config, {
      ami_id             = data.aws_ami.linux.id
      subnet_id          = aws_subnet.private.id
      security_group_ids = [aws_security_group.instances.id]
    })
  }
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  backend "s3" {
    bucket = "terraform-state-ruhickey"
    key = "statefiles/state"
    region = "eu-west-1"
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region = "eu-west-1"
}

#resource "aws_instance" "app_server" {
#  ami     = data.aws_ami.amazon-linux-2.id
#  instance_type     = "t2.micro"
#
#  tags = {
#    Name = "ExampleServer-${var.disambiguator}"
#  }
#}

data "aws_ami" "amazon-linux-2" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-ebs"]
  }

  owners = ["amazon"]
}
terraform {
  required_version = ">= 1.12.0, < 1.14.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.100.0"
    }
  }
  backend "s3" {}
}

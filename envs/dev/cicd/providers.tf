terraform {
  required_version = ">= 1.8.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.17"
    }
  }
  backend "s3" {}
}

provider "aws" {
  region = var.region
}
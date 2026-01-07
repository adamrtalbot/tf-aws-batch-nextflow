# Terraform and Provider Requirements
# This module requires Terraform 1.0+ and uses AWS and Seqera providers

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    seqera = {
      source  = "seqeralabs/seqera"
      version = ">= 0.1"
    }
  }
}

# AWS Provider
provider "aws" {
  region  = var.region
  profile = var.profile
}

provider "seqera" {
  server_url  = var.seqera_server_url
  bearer_auth = var.seqera_access_token
}

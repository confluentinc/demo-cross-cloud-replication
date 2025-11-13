terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    confluent = {
      source = "confluentinc/confluent"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "confluent" {
  cloud_api_key    = var.confluent_cloud_api_key
  cloud_api_secret = var.confluent_cloud_api_secret
}

# https://docs.confluent.io/cloud/current/networking/peering/aws-peering.html
# Create a VPC Peering Connection to Confluent Cloud on AWS
provider "aws" {
  region = var.aws_region
}

provider "azurerm" {
  features {}
}
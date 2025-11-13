variable "prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "cl"
}

variable "confluent_cloud_api_key" {
  description = "Confluent Cloud API Key (also referred as Cloud API ID)."
  type        = string
}

variable "confluent_cloud_api_secret" {
  description = "Confluent Cloud API Secret."
  type        = string
  sensitive   = true
}


variable "aws_region" {
  description = "The cloud region for your infrastructure"
  type        = string
  default     = "us-east-2"
}

variable "azure_region" {
  description = "Azure region name (e.g., 'East US' or 'eastus')"
  type        = string
  default     = "East US"
}
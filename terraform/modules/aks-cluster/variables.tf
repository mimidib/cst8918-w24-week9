# variables without a default will be filled in by the environment variable file
variable "label_prefix" {
  default     = "h09-dib00016"
  description = "Prefix for all resources created by this Terraform configuration"
}

variable "location" {
  type        = string
  description = "The location where the resource will be created"
}

variable "environment" {
  type        = string
  description = "The deployment environment for the resource (e.g., dev, test, prod)"
}

variable "vm_size" {
  type        = string
  description = "The size of the virtual machines in the AKS cluster"
}
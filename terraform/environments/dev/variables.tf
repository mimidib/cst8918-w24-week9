# declares the shape of variables for this root module (environments/dev).
# values come from terraform.tfvars; main.tf forwards them into child modules.
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
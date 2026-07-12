# Configure the Azure provider
terraform {            # where we set terraform settings
  required_providers { # where we define version constraints for each provider 
    azurerm = {
      source  = "hashicorp/azurerm" # can define an optoinal hostname, a namespace and a provider type. In this case we are using the hashicorp namespace and the azurerm provider type
      version = "4.80.0"
    }
  }
  required_version = ">= 1.1.0" # terraform version constraint. This helps us curb Terraform defaulting to `latest` and introducing breaking changes.
}

provider "azurerm" { # configure the provider plugin to create and manage resources in Azure
  features {}
}
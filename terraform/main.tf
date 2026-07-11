# Configure the Azure provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0.2"
    }
  }

  required_version = ">= 1.1.0"
}

provider "azurerm" {
  features {}
}

  resource "azurerm_resource_group" "rg" {
  name     = "${var.label_prefix}-rg"
  location = "canadacentral"
}

resource "azurerm_public_ip" "webserver" {
  name                = "${var.label_prefix}A06PublicIP"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Dynamic"
}

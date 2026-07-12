#  wires all of the variables and their values to the modules specified below, assigning our var.location to their location variable

module "aks-cluster" {
  source      = "../../modules/aks-cluster"
  location    = var.location
  environment = var.environment
  vm_size     = var.vm_size
}



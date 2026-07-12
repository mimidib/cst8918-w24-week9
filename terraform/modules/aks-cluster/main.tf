resource "azurerm_resource_group" "rg" {
  name     = "${var.label_prefix}-rg"
  location = var.location
}

resource "azurerm_kubernetes_cluster" "aks-cluster" { # no kubernetes_version  version specified = latest version
  name                = "${var.label_prefix}-aks-cluster"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "${var.label_prefix}-aks-cluster-dns"

  default_node_pool { # a nested block for complex settings bundled together.
    name                 = "default"
    node_count           = 1
    vm_size              = var.vm_size
    auto_scaling_enabled = true
    min_count            = 1
    max_count            = 3
    type                 = "VirtualMachineScaleSets"
  }

  lifecycle {
    ignore_changes = [
      default_node_pool[0].node_count,
    ] # helps us ignore resource attributes that are changed outside of terraform (lets us share responsibility in managing autoscaling settings with Azure, wihtout it Terraform will always change back scaling the node pool count back to 1 when it auto-scales.)
  }

  identity {
    type = "SystemAssigned" # a managed identity tied just to this aks cluster resource, deleted automatically when the resource is deleted. This gives the cluster permissions to interract with the Azure API to manage, create and configure Azure resources. (we will assign a RBAC role to this identity later)
  }

  tags = {
    Environment = var.environment
  }
}

output "client_certificate" {
  value     = azurerm_kubernetes_cluster.aks-cluster.kube_config[0].client_certificate
  sensitive = true
}

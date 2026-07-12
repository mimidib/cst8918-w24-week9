# outputs of our aks_cluster module kubernetes config - sensitive . we will use this to connect to the AKS cluster using hte kubectl command
output "kube_config" {
  value = azurerm_kubernetes_cluster.aks-cluster.kube_config_raw

  sensitive = true
}
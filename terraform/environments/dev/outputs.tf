# this file re-exposes the output form aks-cluster so that it can be used in the dev environment. if we didn't do this, the output from the module would not be available to the dev environment. 
output "kube_config" {
  value     = module.aks-cluster.kube_config
  sensitive = true
}
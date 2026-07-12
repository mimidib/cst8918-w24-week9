# My Plan for H09

This document captures my thinking as I worked through the H09 assignment. It walks through my thought process for planning the AKS cluster and its supporting infrastructure — the resources I needed, the decisions I weighed, and the issues I ran into along the way.

## AKS Cluster Setup

I created the AKS cluster using the `azurerm_kubernetes_cluster` resource: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kubernetes_cluster

- AKS handles VM NIC creation automatically as part of the underlying VM Scale Set — I don't need to create NICs manually the way I would for standalone VMs.
- I considered whether I needed a VNet and subnet (`vnet_subnet_id`) for the node pool. AKS can run without one specified at all — if left out, it auto-creates its own managed VNet behind the scenes.
- CNI (Container Network Interface) mode determines how pod networking is assigned. AKS offers two options:
  - **Kubenet** (basic) — nodes get IPs from the subnet, but pods get IPs from a separate internal overlay network. Simpler, but less native integration with Azure networking.
  - **Azure CNI** (advanced) — each pod gets a real IP directly from the VNet subnet, in the same address space as the nodes. More integration, but it consumes subnet IPs quickly, so the subnet needs to be sized for both nodes and pods.
- Kubenet's main trade-off is that pods aren't directly reachable by pod IP from outside the VNet (e.g. another VM or on-prem network addressing a pod directly). That doesn't apply here — `store-front` is exposed externally via a `LoadBalancer` Service, but that traffic hits Azure's load balancer and gets routed through a node to the right pod via `kube-proxy`; it never needs to address a pod IP directly. So Kubenet's downside doesn't come into play even though `store-front` is reachable from the browser — I went with the default managed VNet and Kubenet.
- I used the `default_node_pool` block to autoscale worker nodes with a minimum of 1 and a maximum of 3, based on resource usage. I do **not** need to manually assign which workload runs on which node (e.g. backends on one node, frontend/RabbitMQ on another) — the Kubernetes scheduler handles pod placement automatically based on resource requests and node capacity.
- Note: the autoscaling argument name changed between provider versions — it's `enable_auto_scaling` in azurerm 3.x, and `auto_scaling_enabled` in azurerm 4.x (see Challenges below).

```hcl
# azurerm ~> 4.x
default_node_pool {
  name                 = "default"
  vm_size              = "Standard_B2s"
  auto_scaling_enabled = true
  min_count            = 1
  max_count            = 3
  type                 = "VirtualMachineScaleSets"
}
```

## Managed Identity & RBAC

- The cluster authenticates using a **system-assigned managed identity**. This lets it securely interact with the Azure API to provision, configure, and manage underlying infrastructure resources, without needing an embedded credential or certificate.
- `SystemAssigned` ties the identity 1:1 to this specific cluster resource, and it's automatically deleted when the cluster is deleted (as opposed to `UserAssigned`, which is a standalone, shareable identity across multiple resources that persists independently).
- To assign an RBAC role to that identity (e.g. `AcrPull` if pulling images from an ACR), my own account needs sufficient permissions first: either the **Owner** role, or **Contributor + User Access Administrator**.
- Reference: https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/guides/managed_service_identity#configuring-a-vm-to-use-a-system-assigned-managed-identity

## Project Structure — Root vs. Child Modules

```txt
terraform/
└── environments/
    └── dev/
        ├── main.tf          # Root module: calls child modules, wires variables in
        ├── variables.tf     # Root module: declares environment-wide variable shapes
        ├── outputs.tf       # Root module: re-exposes module outputs (e.g. kube_config)
        ├── terraform.tfvars # Supplies actual values for this environment
        └── versions.tf      # Provider requirements + provider configuration
└── modules/
    ├── aks-cluster/         # Child module: AKS cluster + resource group
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    └── network/             # Child module: networking resources (if used)
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

Key things I learned about this pattern:
- Modules are generic, reusable blueprints with no hardcoded, environment-specific values.
- Environment folders are thin config layers — they call a module and pass in environment-specific variable values.
- The dependency only ever flows one direction: environment → module. A module never knows or assumes anything about which environment is calling it.
- Provider configuration (`provider "azurerm" { features {} }`) only belongs in the root module; child modules only declare `required_providers` version constraints, not the actual provider config.
- Variables don't automatically pass between files — each handoff (`.tfvars` → root `variables.tf` → module call in `main.tf` → module's own `variables.tf`) has to be wired explicitly by name.
- Outputs work the same way in reverse: a module's output isn't automatically visible outside it — the root needs its own `outputs.tf` that references `module.<name>.<output>` to surface it.

Reference for variable definition files and precedence: https://developer.hashicorp.com/terraform/language/values/variables#variable-definition-files

## Connecting kubectl to the Cluster

Something I initially got confused about: how does `kubectl` know to deploy `sample-app.yaml` onto the specific AKS cluster Terraform created?

The answer: the cluster's `kube_config_raw` output is written to a local file, which `kubectl` then uses as its connection context:

```bash
echo "$(terraform output kube_config)" > ./kubeconfig
export KUBECONFIG=./kubeconfig
```

One gotcha I hit: `KUBECONFIG` stores a literal path string (e.g. `./kubeconfig`), and that relative path is re-resolved against whatever directory the shell is *currently* in every time a `kubectl` command runs — it isn't "remembered" relative to wherever it was set. If I `cd` elsewhere after exporting it, `kubectl` can no longer find the file at that relative path and silently falls back to its default of `localhost:8080`, producing a "connection refused" error that looks unrelated to the actual cause.

After fixing that path issue and confirming `store-front`'s `LoadBalancer` Service had a provisioned `EXTERNAL-IP` (see Fig. 1), I was able to reach the storefront in the browser at that address:

![Storefront reachable in browser](/images/store-front.png)
*Fig. 1 — Storefront application successfully loaded via the `store-front` LoadBalancer Service's external IP.*

## Challenges

**1. Retired Azure API version**
My initial `azurerm` provider pin (`~> 3.0.2`) called AKS using a retired preview API version (`2022-01-02-preview`), which Azure rejected outright. I confirmed this wasn't a `kubernetes_version` issue — the version numbers in the error (`2022-01-02-preview`, `2024-05-01`, etc.) were Azure Resource Manager API versions, not Kubernetes versions (Kubernetes versions follow `x.y.z` semver; ARM API versions are date-stamped). Since there was no reason to stay pinned to an old version, I checked the current stable release on the Terraform Registry and upgraded to `azurerm ~> 4.80.0`. This also meant renaming `enable_auto_scaling` to `auto_scaling_enabled` to match the 4.x provider's field name.

**2. `order-service` CrashLoopBackOff — AMQP protocol mismatch**

`order-service` repeatedly restarted with `State: Terminated`, `Reason: Error`, `Exit Code: 0`.

Before digging into logs, I first ruled out the two most common causes of a crash-looping pod based on the exit code and reason alone: an OOM kill would show `Reason: OOMKilled` with `Exit Code: 137`, and a CPU limit can't terminate a container at all (Kubernetes only throttles CPU, it never kills for it). Since I saw `Reason: Error` and `Exit Code: 0` instead — normally the signature of a process exiting on its own, cleanly — that pointed to an application-level issue rather than a resource-limit one, which is what I investigated next.

- `kubectl logs` showed a Fastify plugin timeout error (`AVV_ERR_PLUGIN_EXEC_TIMEOUT`) — a message-queue-related plugin never finished initializing.
- The `wait-for-rabbitmq` initContainer only confirms TCP port 5672 is reachable (`nc -zv`) before the main container starts; it doesn't confirm RabbitMQ has finished its own internal startup and is ready to complete an application-level protocol handshake.
- RabbitMQ's own logs showed the connection authenticating successfully, then getting rejected on a specific attach attempt: `Attach rejected: {unknown_destination,"/management"}`, followed by the client closing the connection.
- Checking `order-service`'s dependencies directly inside the running container (`kubectl exec ... cat package.json`, no source repo needed) showed `@azure/service-bus`, `rhea`, and `rabbitmq-amqp-js-client` — libraries built around **AMQP 1.0** and Azure Service Bus specifically.

**Likely root cause (based on the evidence above, not independently verified against the client library's source):** `order-service` appears to have originally been built against Azure Service Bus, which speaks AMQP 1.0 and supports a management-node handshake as part of client startup. Here, it's pointed at RabbitMQ instead, using RabbitMQ's `rabbitmq_amqp1_0` plugin. My working theory is that RabbitMQ's AMQP 1.0 implementation doesn't support the same management-node feature the Service-Bus-oriented client tries to use, so that specific attach is rejected, the client aborts the connection, and the app's plugin registration hangs until Fastify's timeout kills it. This fits the logs and dependency list, but I did not confirm it directly against `rabbitmq-amqp-js-client`'s documentation or source.

This is a protocol-compatibility limitation in the provided sample app (built for Azure Service Bus) running against RabbitMQ — not a Terraform or infrastructure configuration issue. The AKS cluster, autoscaling, networking, and `store-front`/`product-service` deployments all function correctly; `order-service`'s crash loop is isolated to this app-level mismatch.

Since this seemed outside of the scope of the assignment, I put this on hold until confirming it's part of the debugging expectations for the assignment.

**What I'd try next, if continuing:**
- Check `rabbitmq-amqp-js-client`'s documentation/GitHub issues for a config option to skip or disable the management-node handshake on connect.
- Try swapping `order-service`'s messaging client to a standard AMQP 0-9-1 library (e.g. `amqplib`), which is RabbitMQ's native protocol and wouldn't attempt a Service-Bus-style management attach at all — though this would mean modifying the provided app code, which may be outside this assignment's scope.
- Confirm with the course instructor/TA whether full end-to-end message flow through `order-service` is required for grading, or whether successful infrastructure provisioning and `store-front` reachability satisfies the assignment's actual scope.
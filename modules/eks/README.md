# EKS Module

Creates an Amazon EKS cluster: the control plane, cluster/node security groups, the IRSA OIDC provider, the cluster IAM role, optional cluster add-ons, an optional KMS key for Secrets encryption, and (via `node_groups.tf`) EKS managed node groups.

## Provenance

This module is a vendored, lightly customized copy of the community [`terraform-aws-modules/terraform-aws-eks`](https://github.com/terraform-aws-modules/terraform-aws-eks) module. The only local addition found in this copy is the `kms_key_arn` variable in `variables.tf` (marked `# Added by devops`) — note that this variable is currently declared but **not referenced** anywhere in `main.tf` or `node_groups.tf` (a dead input; see the root README's Known Issues). Everything else — resource logic, the nested `modules/eks-managed-node-group`, `modules/_user_data`, and `modules/capability` sub-modules, and the `templates/` user-data templates — is unmodified upstream code.

The upstream project is Apache-2.0 licensed; that license applies to this vendored copy's original code, separately from the MIT license covering the rest of this repository (see the root [`LICENSE`](../../LICENSE)).

If you need full documentation for the underlying resource surface (every input/output, including the deeply nested `eks_managed_node_groups`/`self_managed_node_groups` object types), the nested sub-modules already carry their own upstream-generated `README.md` files:

- [`modules/eks-managed-node-group/README.md`](modules/eks-managed-node-group/README.md)
- [`modules/_user_data/README.md`](modules/_user_data/README.md)
- [`modules/capability/README.md`](modules/capability/README.md)

## Usage

```hcl
module "eks" {
  source = "../../modules/eks"

  name                                     = var.cluster_name
  kubernetes_version                       = var.kubernetes_version
  endpoint_public_access                   = false
  enable_cluster_creator_admin_permissions = true
  enable_irsa                              = true

  vpc_id                   = var.vpc_id
  control_plane_subnet_ids = [var.subnet_private_a, var.subnet_private_b]
  subnet_ids               = [var.subnet_private_a, var.subnet_private_b]

  create_kms_key = false
  encryption_config = {
    resources        = ["secrets"]
    provider_key_arn = data.aws_kms_key.app-data.arn
  }

  eks_managed_node_groups = {
    (var.name) = {
      instance_types = var.instance_type
      min_size       = var.min_size
      max_size       = var.max_size
      desired_size   = var.desired_size
    }
  }
}
```

See [`environments/qa/main.tf`](../../environments/qa/main.tf) for the full, real-world invocation used by this repository.

## Inputs (most commonly used)

The module exposes well over a hundred optional inputs (full list in `variables.tf`); these are the ones actually exercised by `environments/qa`:

| Name | Type | Description | Default |
|---|---|---|---|
| `create` | `bool` | Controls if resources should be created at all | `true` |
| `name` | `string` | EKS cluster name | `""` |
| `kubernetes_version` | `string` | Cluster Kubernetes `<major>.<minor>` version | `null` |
| `vpc_id` | `string` | VPC ID for the cluster security group | `null` |
| `subnet_ids` | `list(string)` | Subnets for node groups (and control plane, if `control_plane_subnet_ids` is empty) | `[]` |
| `control_plane_subnet_ids` | `list(string)` | Subnets for the control plane ENIs | `[]` |
| `endpoint_public_access` | `bool` | Whether the public API endpoint is enabled | `false` |
| `endpoint_private_access` | `bool` | Whether the private API endpoint is enabled | `true` |
| `enable_irsa` | `bool` | Creates an OIDC provider for IRSA | `true` |
| `enable_cluster_creator_admin_permissions` | `bool` | Grants the Terraform caller cluster-admin via an access entry | `false` |
| `create_kms_key` | `bool` | Whether this module should create its own KMS key (via the nested `modules/kms` call) for Secrets encryption | `false` |
| `encryption_config` | `object` | `resources` + `provider_key_arn` for Secrets envelope encryption | `{}` |
| `eks_managed_node_groups` | `map(object)` | Map of EKS managed node group definitions (delegated to `modules/eks-managed-node-group`) | `null` |
| `self_managed_node_groups` | `map(object)` | Map of self-managed (ASG-based) node group definitions | `null` |
| `create_cloudwatch_log_group` | `bool` | Creates a `/aws/eks/<name>/cluster` log group | `true` |
| `cloudwatch_log_group_retention_in_days` | `number` | Log retention | `90` |
| `kms_key_arn` | `string` | **Locally added, currently unused input** — declared but not referenced in this module's resources | `null` |

## Outputs (most commonly used)

| Name | Description |
|---|---|
| `cluster_name` | Name of the created cluster. |
| `cluster_endpoint` | Kubernetes API server endpoint. |
| `cluster_certificate_authority_data` | Base64-encoded cluster CA certificate. |
| `cluster_arn`, `cluster_id`, `cluster_version`, `cluster_status` | Cluster identity/status attributes. |
| `oidc_provider` | OIDC issuer URL (no `https://` prefix) — used to build IRSA trust policies. |
| `oidc_provider_arn` | ARN of the IRSA OIDC provider. |
| `cluster_primary_security_group_id` | EKS-managed primary security group ID (control-plane-to-data-plane). |
| `cluster_security_group_id` / `node_security_group_id` | IDs of the security groups this module creates. |
| `kms_key_arn` / `kms_key_id` / `kms_key_policy` | Attributes of the KMS key created by the nested `modules/kms` call — only populated when `create_kms_key = true`. In `environments/qa`, `create_kms_key = false`, so these will be `null`. |
| `eks_managed_node_groups` | Map of attributes for every managed node group created. |
| `eks_managed_node_groups_autoscaling_group_names` | Flat list of ASG names backing the managed node groups. |

## Dependencies

- Calls `./modules/eks-managed-node-group` for each entry in `var.eks_managed_node_groups`.
- Calls `../kms` (this repo's [`modules/kms`](../kms/README.md)) when `var.create_kms_key = true`. `environments/qa` sets this to `false` and instead supplies an existing key ARN via `encryption_config.provider_key_arn`.
- Requires providers: `aws (>= 6.28)`, `tls (>= 4.0)`, `time (>= 0.9)` — declared in `versions.tf`.

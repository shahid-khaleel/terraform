# Environment: `qa`

This is the root Terraform configuration for the **QA** environment — the only environment currently defined in this repository. It owns its own state, providers, and variable values, and calls the reusable [`modules/eks`](../../modules/eks/README.md) module.

## Purpose

Provisions:

- An Amazon EKS cluster (via `modules/eks`) with a single managed node group, private-only API endpoint, IRSA enabled, and Kubernetes Secrets encrypted using an existing KMS key (`alias/app-data`).
- IAM roles + Helm releases for the **Cluster Autoscaler** and the **AWS Load Balancer Controller**, both authenticating via IRSA.
- An `IngressClass` / `Ingress` pair for the AWS Load Balancer Controller to reconcile into an ALB.
- `HorizontalPodAutoscaler` (v2) resources for a fixed set of application Deployments (`var.hpa_targets`).
- `ENIConfig` custom-resources associating existing subnets with a secondary VPC CIDR (no new CIDR block or subnets are created — see the commented-out block at the bottom of `main.tf`).
- Local bootstrap steps (`null_resource` + `local-exec`): updating kubeconfig, installing `metrics-server`, and setting CNI custom-networking environment variables on the `aws-node` DaemonSet.

This environment does **not** create the VPC, subnets, KMS key, or ACM certificate it depends on — those are looked up via data sources and must already exist in the target AWS account.

## File map

| File | Purpose |
|---|---|
| `backend.tf` | Terraform state backend (currently local; S3+DynamoDB block present but commented out). |
| `providers.tf` | AWS, Kubernetes, and Helm provider configuration (Kubernetes/Helm auth via `aws eks get-token`). |
| `version.tf` | Required provider versions (`aws`, `kubernetes`, `helm`, `http`). |
| `variables.tf` | Input variable declarations for this environment. |
| `terraform.tfvars` | Variable values. **Currently all blank placeholders** — see [Security note](#security-note) below. |
| `localvalues.tf` | Computed `local.name` and `local.common_tags`. |
| `main.tf` | Core resources: EKS module call, Cluster Autoscaler, AWS Load Balancer Controller, Ingress, ENIConfig, kubeconfig/metrics-server bootstrap. |
| `hpa-based-on-app.tf` | `HorizontalPodAutoscaler` resources for `var.hpa_targets`. |
| `output.tf` | Environment outputs (cluster identity, networking, node group config, KMS key, AMI, ACM certificate). |

## Inputs

| Name | Type | Description | Default |
|---|---|---|---|
| `cluster_name` | `string` | EKS cluster name | — (required) |
| `kubernetes_version` | `string` | EKS cluster Kubernetes version | — (required) |
| `region` | `string` | AWS region for the deployment | — (required; `terraform.tfvars` defaults to `ap-south-1`) |
| `vpc_id` | `string` | Existing VPC ID | — (required) |
| `subnet_private_a` / `subnet_private_b` | `string` | Existing private subnet IDs | — (required) |
| `node_group_name` | `string` | EKS node group name | — (required) |
| `name` | `string` | Name used as the managed node group key/tag | — (required) |
| `min_size` / `max_size` / `desired_size` | `number` | Node group scaling bounds | — (required) |
| `ami_type` | `string` | Node group AMI type | — (required; `terraform.tfvars` defaults to `AL2023_x86_64_STANDARD`) |
| `instance_type` | `list(string)` | Node group instance type(s) | — (required; `terraform.tfvars` defaults to `["m6i.xlarge"]`) |
| `keypair` | `string` | EC2 key pair name for node SSH access | — (required) |
| `autoscaling_group_arn` | `string` | ASG ARN referenced by an extra IAM policy document (`data.aws_iam_policy_document.default`) | — (required) |
| `bootstrap_self_managed_addons` | `bool` | Whether to bootstrap self-managed add-ons | `false` |
| `sbu` | `string` | Business division / owner tag | — (required) |
| `environment` | `string` | Environment name prefix | — (required) |
| `global_tags` | `map(string)` | Tags applied via the AWS provider's `default_tags` | `{}` |
| `AZ1` / `AZ2` | `string` | Availability zones for `ENIConfig` custom networking | — (required) |
| `subnet-test-private-a-secondary` / `subnet-test-private-b-secondary` | `string` | Subnet IDs used as the secondary-CIDR subnet for each `ENIConfig` | — (required) |
| `hpa_targets` | `set(string)` | Deployment names to create an HPA for | `["test-core-qa", "test2-core-qa", "test2-workflow-qa"]` |

**Note:** `terraform.tfvars` in this repository currently has **empty values for every one of the required variables above**. You must populate it (or supply values via `-var`/`TF_VAR_*`/a separate gitignored `.tfvars` file) before `terraform plan`/`apply` will succeed.

## Outputs

| Name | Description |
|---|---|
| `cluster_name`, `kubernetes_version`, `region` | Echoes of the corresponding input variables. |
| `vpc_id`, `private_subnets` | Networking identifiers used by the cluster. |
| `node_group_name` | EKS node group name. |
| `ami_type`, `instance_type` | Node group compute configuration. |
| `node_group_scaling` | Object with `min`/`max`/`desired`. |
| `aws_kms_key` | KMS key ID resolved from the `alias/app-data` alias. **Currently broken** — see [Known Issues](../../README.md#known-issues--recommendations) in the root README (data source name mismatch). |
| `ami_id` | Resolved AMI ID for worker nodes. |
| `acm_certificate_id` / `acm_certificate_arn` / `acm_certificate_status` | Identifiers for the existing ACM certificate used by the Ingress. |

## Dependencies

- [`modules/eks`](../../modules/eks/README.md) — provisions the EKS control plane and managed node group.
- Pre-existing (not created here): a VPC + two private subnets, a KMS key aliased `alias/app-data`, an ACM certificate covering `*.test.com`, and a VPC tagged `Name=vpc-test-79`.
- External Helm charts: `kubernetes-sigs/aws-load-balancer-controller` via `aws.github.io/eks-charts` (pinned `1.12.0`), and `cluster-autoscaler` via `kubernetes.github.io/autoscaler` (unpinned — see root README's Known Issues).
- Local tooling: `aws` CLI and `kubectl` on the machine running Terraform (used by `local-exec` provisioners).

## Example usage

```bash
cd environments/qa
terraform init
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

(`-var-file=terraform.tfvars` is implicit — Terraform loads a file with that exact name automatically — shown here for clarity.)

## Security note

Every value in the tracked `terraform.tfvars` is currently an empty string, empty list entry, or empty map — there are **no real secrets, account IDs, or credentials checked into this file today**. That said, because the filename `terraform.tfvars` is auto-loaded by Terraform and is the natural place to put real deployment values, there is a real risk that a future edit fills it in with production-adjacent values and commits them. See the root [README's Security considerations](../../README.md#security-considerations) for the recommended fix (rename this file's role to a `.tfvars.example` template and use a gitignored file for real values).

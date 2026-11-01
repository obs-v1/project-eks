# ─────────────────────────────────────────────────────────────────────────────
#  project-eks/cluster — two EKS clusters (observability + bankobs), each in its
#  own VPC, peered, sharing a private DNS zone for in-cluster telemetry ingest.
#  Provisioned entirely with Terraform. One `terraform apply`.
# ─────────────────────────────────────────────────────────────────────────────
terraform {
  required_version = ">= 1.5"

  required_providers {
    aws        = { source = "hashicorp/aws", version = "~> 6.0" }
    helm       = { source = "hashicorp/helm", version = "~> 3.0" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 3.0" }
    tls        = { source = "hashicorp/tls", version = "~> 4.0" }
    cloudinit  = { source = "hashicorp/cloudinit", version = "~> 2.3" }
  }
}

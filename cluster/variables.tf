# ── Required inputs the student supplies (via tfvars or the Makefile) ─────────
variable "public_hosted_zone_id" {
  description = "Route53 PUBLIC hosted zone ID for the UI hostnames (grafana.<domain>, bankobs.<domain>, …)."
  type        = string
}

variable "public_domain_name" {
  description = "Base public domain, e.g. lab.example.com. UIs are published as <svc>.<public_domain_name>."
  type        = string
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN (wildcard *.<public_domain_name>) used by the public Traefik NLB for TLS."
  type        = string
}

# ── Region / cluster basics (safe defaults) ──────────────────────────────────
variable "aws_region" {
  description = "AWS region for both clusters."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Name prefix for every resource."
  type        = string
  default     = "obs-v1"
}

variable "eks_version" {
  description = "Kubernetes version for both clusters. Bump to the latest EKS standard-support release; check with: aws eks describe-cluster-versions"
  type        = string
  default     = "1.34"
}

# ── Networking ────────────────────────────────────────────────────────────────
variable "obs_vpc_cidr" {
  description = "CIDR for the observability VPC (must not overlap the bankobs VPC — they are peered)."
  type        = string
  default     = "10.10.0.0/16"
}

variable "bankobs_vpc_cidr" {
  description = "CIDR for the bankobs VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "private_dns_domain" {
  description = "Private Route53 zone shared by both VPCs for telemetry ingest (e.g. otel-collector.<here>)."
  type        = string
  default     = "obs.internal"
}

variable "public_api_access_cidrs" {
  description = "CIDRs allowed to reach the (public) EKS API server. Default: anywhere, so you can kubectl from any laptop."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# ── Spot node groups ──────────────────────────────────────────────────────────
# A diversified instance set per group so a Spot interruption in one pool doesn't
# drain the whole cluster — the Spot allocation strategy spreads across them.
variable "obs_node_instance_types" {
  description = "Instance types for the observability cluster's Spot node group."
  type        = list(string)
  default     = ["m5.2xlarge", "m5a.2xlarge", "m6i.2xlarge", "m5n.2xlarge"]
}

variable "obs_node_scaling" {
  description = "min/desired/max for the observability Spot node group."
  type        = object({ min = number, desired = number, max = number })
  default     = { min = 2, desired = 3, max = 6 }
}

variable "bankobs_node_instance_types" {
  description = "Instance types for the bankobs cluster's Spot node group (bigger: 60 svcs + stateful DBs)."
  type        = list(string)
  default     = ["m5.4xlarge", "m5a.4xlarge", "m6i.4xlarge", "m5n.4xlarge"]
}

variable "bankobs_node_scaling" {
  description = "min/desired/max for the bankobs Spot node group."
  type        = object({ min = number, desired = number, max = number })
  default     = { min = 3, desired = 4, max = 10 }
}

variable "tags" {
  description = "Extra tags applied to everything."
  type        = map(string)
  default     = {}
}

# ── EKS: observability cluster ───────────────────────────────────────────────
module "eks_observability" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.24"

  cluster_name    = local.obs_cluster_name
  cluster_version = var.eks_version

  # Public API so you can kubectl from anywhere; private access on too, for the
  # in-VPC/peered paths.
  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = var.public_api_access_cidrs
  cluster_endpoint_private_access      = true

  enable_irsa                              = true
  enable_cluster_creator_admin_permissions = true
  authentication_mode                      = "API_AND_CONFIG_MAP"

  vpc_id     = module.vpc_observability.vpc_id
  subnet_ids = module.vpc_observability.private_subnets

  # EBS CSI is added separately (addons.tf) to avoid an OIDC dependency cycle.
  cluster_addons = {
    coredns    = { most_recent = true }
    kube-proxy = { most_recent = true }
    vpc-cni    = { most_recent = true, before_compute = true }
  }

  eks_managed_node_groups = {
    spot = {
      instance_types = var.obs_node_instance_types
      capacity_type  = "SPOT"
      min_size       = var.obs_node_scaling.min
      max_size       = var.obs_node_scaling.max
      desired_size   = var.obs_node_scaling.desired
      labels         = { role = "observability" }
    }
  }

  tags = local.tags
}

# ── EKS: bankobs cluster ─────────────────────────────────────────────────────
module "eks_bankobs" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.24"

  cluster_name    = local.bankobs_cluster_name
  cluster_version = var.eks_version

  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = var.public_api_access_cidrs
  cluster_endpoint_private_access      = true

  enable_irsa                              = true
  enable_cluster_creator_admin_permissions = true
  authentication_mode                      = "API_AND_CONFIG_MAP"

  vpc_id     = module.vpc_bankobs.vpc_id
  subnet_ids = module.vpc_bankobs.private_subnets

  cluster_addons = {
    coredns    = { most_recent = true }
    kube-proxy = { most_recent = true }
    vpc-cni    = { most_recent = true, before_compute = true }
  }

  eks_managed_node_groups = {
    spot = {
      instance_types = var.bankobs_node_instance_types
      capacity_type  = "SPOT"
      min_size       = var.bankobs_node_scaling.min
      max_size       = var.bankobs_node_scaling.max
      desired_size   = var.bankobs_node_scaling.desired
      labels         = { role = "bankobs" }
    }
  }

  tags = local.tags
}

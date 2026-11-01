# ── EBS CSI driver (managed addon, IRSA) + gp3 default StorageClass ──────────
resource "aws_eks_addon" "ebs_csi" {
  cluster_name                = var.cluster_name
  addon_name                  = "aws-ebs-csi-driver"
  service_account_role_arn    = var.ebs_csi_role_arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  tags                        = var.tags
}

resource "kubernetes_storage_class" "gp3" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }
  storage_provisioner    = "ebs.csi.aws.com"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true
  parameters = {
    type   = "gp3"
    fsType = "ext4"
  }
  depends_on = [aws_eks_addon.ebs_csi]
}

# ── Cluster Autoscaler ───────────────────────────────────────────────────────
resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  version    = "9.43.2"
  namespace  = "kube-system"

  set {
    name  = "autoDiscovery.clusterName"
    value = var.cluster_name
  }
  set {
    name  = "awsRegion"
    value = var.region
  }
  set {
    name  = "rbac.serviceAccount.name"
    value = "cluster-autoscaler"
  }
  set {
    name  = "rbac.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = var.autoscaler_role_arn
  }
  set {
    name  = "extraArgs.balance-similar-node-groups"
    value = "true"
  }
  set {
    name  = "extraArgs.skip-nodes-with-system-pods"
    value = "false"
  }
}

# ── external-dns (ingress + service sources; public UIs + private collector) ──
resource "helm_release" "external_dns" {
  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns"
  chart      = "external-dns"
  version    = "1.15.0"
  namespace  = "kube-system"

  set {
    name  = "provider.name"
    value = "aws"
  }
  set {
    name  = "serviceAccount.name"
    value = "external-dns"
  }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = var.external_dns_role_arn
  }
  set {
    name  = "policy"
    value = "upsert-only" # never delete records it didn't create; safe in a shared zone
  }
  set {
    name  = "txtOwnerId"
    value = var.cluster_name
  }
  set {
    name  = "sources[0]"
    value = "ingress"
  }
  set {
    name  = "sources[1]"
    value = "service"
  }
  dynamic "set" {
    for_each = var.external_dns_domain_filters
    content {
      name  = "domainFilters[${set.key}]"
      value = set.value
    }
  }
}

# ── Traefik ingress controller (public NLB, TLS terminated at the NLB via ACM) ─
resource "helm_release" "traefik" {
  name             = "traefik"
  repository       = "https://traefik.github.io/charts"
  chart            = "traefik"
  version          = "33.0.0"
  namespace        = "traefik"
  create_namespace = true

  values = [yamlencode({
    service = {
      type = "LoadBalancer"
      annotations = {
        "service.beta.kubernetes.io/aws-load-balancer-type"             = "nlb"
        "service.beta.kubernetes.io/aws-load-balancer-scheme"           = "internet-facing"
        "service.beta.kubernetes.io/aws-load-balancer-ssl-cert"         = var.acm_certificate_arn
        "service.beta.kubernetes.io/aws-load-balancer-ssl-ports"        = "websecure"
        "service.beta.kubernetes.io/aws-load-balancer-backend-protocol" = "tcp"
      }
    }
    # TLS is terminated at the NLB (ACM), so Traefik itself serves plain HTTP on
    # both entrypoints — the NLB forwards decrypted traffic to websecure.
    ports = {
      web = {
        port        = 8000
        exposedPort = 80
      }
      websecure = {
        port        = 8443
        exposedPort = 443
        tls         = { enabled = false }
      }
    }
    ingressClass = {
      enabled        = true
      isDefaultClass = true
    }
    # Publish Traefik's LB address onto each Ingress's status, so external-dns
    # (source=ingress) can create the DNS records pointing at the NLB.
    providers = {
      kubernetesIngress = {
        publishedService = {
          enabled = true
        }
      }
    }
  })]
}

# ─────────────────────────────────────────────────────────────────────────────
#  project-eks/cluster — two EKS clusters (observability + bankobs) with Terraform
#
#  Pass the three required inputs as make args (or put them in terraform.tfvars):
#    make apply ZONE_ID=Z0... DOMAIN=lab.example.com ACM_ARN=arn:aws:acm:...:certificate/...
#
#  Targets: init · plan · apply · destroy · kubeconfig · output
# ─────────────────────────────────────────────────────────────────────────────
REGION ?= us-east-1

# Map friendly make args → TF_VAR_* so the student doesn't touch tfvars if they
# don't want to. Anything already in terraform.tfvars still works.
ifdef ZONE_ID
export TF_VAR_public_hosted_zone_id = $(ZONE_ID)
endif
ifdef DOMAIN
export TF_VAR_public_domain_name = $(DOMAIN)
endif
ifdef ACM_ARN
export TF_VAR_acm_certificate_arn = $(ACM_ARN)
endif
# ADMIN_ARN: grant cluster-admin to an extra principal (the role running apply, e.g. an EC2
# instance role). Needed when not applying as an interactive SSO/user principal.
#   make apply ... ADMIN_ARN=arn:aws:iam::<acct>:role/workstation
ifdef ADMIN_ARN
export TF_VAR_cluster_admin_arns = ["$(ADMIN_ARN)"]
endif
export TF_VAR_aws_region = $(REGION)

.PHONY: init plan apply destroy clean-lbs fmt validate kubeconfig output

init:
	terraform init

fmt:
	terraform fmt -recursive

validate:
	terraform validate

plan: init
	terraform plan

apply: init
	terraform apply -auto-approve
	@$(MAKE) kubeconfig     # point kubectl at both clusters so the obs/app deploys work right away

# Full teardown. The Traefik and OTLP-collector NLBs are created by the in-tree AWS
# cloud provider from k8s LoadBalancer Services, NOT by Terraform — so they must be
# deleted FIRST. Leaving them orphans their ENIs + SG rules and makes `terraform
# destroy` hang on VPC/subnet deletion. Order: delete LB Services → wait for AWS to
# reap the load balancers → terraform destroy (clusters, nodegroups, VPCs, peering,
# private zone, IAM).
destroy: clean-lbs
	@echo "⏳ waiting for cloud load balancers in both VPCs to disappear..."
	@OBS_VPC=$$(terraform output -raw observability_vpc_id 2>/dev/null); \
	 BNK_VPC=$$(terraform output -raw bankobs_vpc_id 2>/dev/null); \
	 for i in $$(seq 1 36); do \
	   n=$$(aws elbv2 describe-load-balancers --region $(REGION) --query "length(LoadBalancers[?VpcId=='$$OBS_VPC' || VpcId=='$$BNK_VPC'])" --output text 2>/dev/null); \
	   m=$$(aws elb describe-load-balancers --region $(REGION) --query "length(LoadBalancerDescriptions[?VPCId=='$$OBS_VPC' || VPCId=='$$BNK_VPC'])" --output text 2>/dev/null); \
	   n=$${n:-0}; m=$${m:-0}; \
	   if [ "$$n" = "0" ] && [ "$$m" = "0" ]; then echo "  ✓ no load balancers left in either VPC"; break; fi; \
	   echo "  still present: $$n NLB(v2) + $$m classic ELB — retry $$i/36"; sleep 10; \
	 done
	terraform destroy -auto-approve
	@echo "  ✓ clusters, VPCs, peering and private zone destroyed."
	@echo "  NOTE: terraform does NOT remove EBS volumes left by StatefulSet PVCs, or the"
	@echo "        public DNS records external-dns created (upsert-only never deletes)."
	@echo "        Delete those by hand if you want a spotless account / zone."

# Delete every type=LoadBalancer Service in both clusters so the AWS cloud provider
# tears down their NLBs/ELBs (and the ENIs/SG rules that would block VPC deletion).
# Best-effort: ignores a cluster/context that is already gone.
clean-lbs:
	-@aws eks update-kubeconfig --region $(REGION) --name $$(terraform output -raw observability_cluster_name 2>/dev/null) --alias $$(terraform output -raw observability_cluster_name 2>/dev/null) >/dev/null 2>&1
	-@aws eks update-kubeconfig --region $(REGION) --name $$(terraform output -raw bankobs_cluster_name 2>/dev/null)       --alias $$(terraform output -raw bankobs_cluster_name 2>/dev/null)       >/dev/null 2>&1
	@for c in $$(terraform output -raw observability_cluster_name 2>/dev/null) $$(terraform output -raw bankobs_cluster_name 2>/dev/null); do \
	  echo "  → deleting LoadBalancer Services in $$c"; \
	  kubectl --context $$c get svc -A -o go-template='{{range .items}}{{if eq .spec.type "LoadBalancer"}}{{.metadata.namespace}} {{.metadata.name}}{{"\n"}}{{end}}{{end}}' 2>/dev/null \
	    | while read ns name; do [ -n "$$name" ] && echo "      - $$ns/$$name" && kubectl --context $$c -n $$ns delete svc $$name --wait=false >/dev/null 2>&1; done; \
	done
	@echo "  (LB Services deleted; AWS is now reaping the NLBs/ELBs)"

# Point kubectl at both clusters (aliases match the cluster names).
kubeconfig:
	@aws eks update-kubeconfig --region $(REGION) --name $$(terraform output -raw observability_cluster_name) --alias $$(terraform output -raw observability_cluster_name)
	@aws eks update-kubeconfig --region $(REGION) --name $$(terraform output -raw bankobs_cluster_name) --alias $$(terraform output -raw bankobs_cluster_name)
	@echo "  ✓ kubeconfig updated for both clusters."

output:
	terraform output

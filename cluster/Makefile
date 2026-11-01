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
export TF_VAR_aws_region = $(REGION)

.PHONY: init plan apply destroy fmt validate kubeconfig output

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

destroy:
	terraform destroy -auto-approve

# Point kubectl at both clusters (aliases match the cluster names).
kubeconfig:
	@aws eks update-kubeconfig --region $(REGION) --name $$(terraform output -raw observability_cluster_name) --alias $$(terraform output -raw observability_cluster_name)
	@aws eks update-kubeconfig --region $(REGION) --name $$(terraform output -raw bankobs_cluster_name) --alias $$(terraform output -raw bankobs_cluster_name)
	@echo "  ✓ kubeconfig updated for both clusters."

output:
	terraform output

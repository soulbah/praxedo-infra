.PHONY: fmt validate plan apply destroy init lint

ENV ?= dev
TF_DIR := terraform

init:
	cd $(TF_DIR) && terraform init -backend-config=envs/backend-$(ENV).hcl

fmt:
	cd $(TF_DIR) && terraform fmt -recursive

validate:
	cd $(TF_DIR) && terraform fmt -recursive -check
	cd $(TF_DIR) && terraform validate

plan:
	cd $(TF_DIR) && terraform workspace select $(ENV) && terraform plan -var-file=envs/$(ENV).tfvars

apply:
	cd $(TF_DIR) && terraform workspace select $(ENV) && terraform apply -var-file=envs/$(ENV).tfvars

destroy:
	cd $(TF_DIR) && terraform workspace select $(ENV) && terraform destroy -var-file=envs/$(ENV).tfvars

lint:
	cd $(TF_DIR) && tflint --recursive

precommit:
	pre-commit run --all-files

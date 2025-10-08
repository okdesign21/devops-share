#REGION ?= eu-central-1
#PROJECT ?= infdev
STATE_PREFIX ?= inf-devops
BACKEND := ../../backend.hcl
ENV ?= dev

.PHONY: init plan apply destroy

init:
	cd envs/$(ENV)/$(STACK) && \
	terraform init -var-file=../../common.tfvars \
	  -backend-config=$(BACKEND) \
	  -backend-config="key=$(STATE_PREFIX)/$(ENV)/$(STACK)/terraform.tfstate" -reconfigure

plan:
	cd envs/$(ENV)/$(STACK) && \
	terraform plan -var-file=../../common.tfvars

apply:
	cd envs/$(ENV)/$(STACK) && \
	terraform apply -var-file=../../common.tfvars -auto-approve

destroy:
	cd envs/$(ENV)/$(STACK) && \
	terraform destroy -var-file=../../common.tfvars -auto-approve
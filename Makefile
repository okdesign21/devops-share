REGION ?= eu-central-1
PROJECT ?= infdev
BACKEND := backend.hcl
ENV ?= dev

.PHONY: init plan apply destroy

init:
	cd envs/$(ENV)/$(STACK) && \
	terraform init -backend-config=$(BACKEND) -backend-config="key=$(ENV)/$(STACK)/terraform.tfstate" -reconfigure

plan:
	cd envs/$(ENV)/$(STACK) && \
	terraform plan -var="project_name=$(PROJECT)" -var="region=$(REGION)"

apply:
	cd envs/$(ENV)/$(STACK) && \
	terraform apply -auto-approve -var="project_name=$(PROJECT)" -var="region=$(REGION)"

destroy:
	cd envs/$(ENV)/$(STACK) && \
	terraform destroy -auto-approve -var="project_name=$(PROJECT)" -var="region=$(REGION)"
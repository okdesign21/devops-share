REGION ?= eu-central-1
PROJECT ?= infdev
BACKEND := ../../backend.hcl

run:
	cd envs/$(ENV)/$(STACK) && \
	terraform init -backend-config=$(BACKEND) -backend-config="key=$(ENV)/$(STACK)/terraform.tfstate" -reconfigure && \
	terraform apply -auto-approve -var="project_name=$(PROJECT)" -var="region=$(REGION)"

destroy:
	cd envs/$(ENV)/$(STACK) && \
	terraform destroy -auto-approve -var="project_name=$(PROJECT)" -var="region=$(REGION)"

STATE_PREFIX ?= inf-devops
BACKEND := ../../backend.hcl
ENV ?= dev
STACK ?= all
STACKS ?= network cicd eks #monitoring

# computed lists: if STACK=all use STACKS, otherwise use single STACK
STACK_LIST := $(if $(filter all,$(STACK)),$(STACKS),$(STACK))
REVERSE_STACKS := $(if $(filter all,$(STACK)),$(shell echo $(STACKS) | awk '{for(i=NF;i>=1;i--) printf "%s ", $$i}'),$(STACK))

.PHONY: init plan apply destroy

init:
	@for s in $(STACK_LIST) ; do \
		echo "== terraform init $$s ==" ; \
		( cd envs/$(ENV)/$$s && terraform init -var-file=../../common.tfvars \
			-backend-config=$(BACKEND) \
			-backend-config="key=$(STATE_PREFIX)/$(ENV)/$$s/terraform.tfstate" -reconfigure ) || exit 1; \
	done

plan:
	@for s in $(STACK_LIST) ; do \
		echo "== terraform plan $$s ==" ; \
		( cd envs/$(ENV)/$$s && terraform plan -var-file=../../common.tfvars ) || exit 1; \
	done

apply:
	@for s in $(STACK_LIST) ; do \
		echo "== terraform apply $$s ==" ; \
		( cd envs/$(ENV)/$$s && terraform apply -var-file=../../common.tfvars -auto-approve ) || exit 1; \
	done

destroy:
	@for s in $(REVERSE_STACKS) ; do \
		echo "== terraform destroy $$s ==" ; \
		( cd envs/$(ENV)/$$s && terraform destroy -var-file=../../common.tfvars -auto-approve ) || exit 1; \
	done

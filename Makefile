STATE_PREFIX ?= inf-devops
BACKEND := ../../backend.hcl
ENV ?= dev
STACK ?= all
STACKS ?= network cicd eks dns

# computed lists: if STACK=all use STACKS, otherwise use single STACK
STACK_LIST := $(if $(filter all,$(STACK)),$(STACKS),$(STACK))
REVERSE_STACKS := $(if $(filter all,$(STACK)),$(shell echo $(STACKS) | awk '{for(i=NF;i>=1;i--) printf "%s ", $$i}'),$(STACK))

.PHONY: init plan apply destroy refresh output validate fmt

init:
	@for s in $(STACK_LIST) ; do \
		echo "== terraform init $$s ==" ; \
		( cd envs/$(ENV)/$$s && terraform init -var-file=../../common.tfvars -upgrade \
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

refresh:
    @for s in $(STACK_LIST) ; do \
        echo "== terraform refresh $$s ==" ; \
        ( cd envs/$(ENV)/$$s && terraform refresh -var-file=../../common.tfvars ) || exit 1; \
    done

output:
    @for s in $(STACK_LIST) ; do \
        echo "== terraform output $$s ==" ; \
        ( cd envs/$(ENV)/$$s && terraform output ) || exit 1; \
    done

validate:
    @for s in $(STACK_LIST) ; do \
        echo "== terraform validate $$s ==" ; \
        ( cd envs/$(ENV)/$$s && terraform validate ) || exit 1; \
    done

fmt:
    @terraform fmt -recursive .

# -------- Terraform Orchestrator Makefile --------
ENV            ?= dev
PROJECT_NAME   ?= proj
STACK          ?= all
STACKS         := network cicd eks eks-addons dns

BACKEND_FILE   := ../../backend.hcl
COMMON_VARS    := ../../common.tfvars

# If STACK=all -> use STACKS; else -> just the specific stack
STACK_LIST     := $(if $(filter all,$(STACK)),$(STACKS),$(STACK))
# Reverse order for destroy-all
REVERSE_STACKS := $(if $(filter all,$(STACK)),$(shell echo $(STACKS) | awk '{for(i=NF;i>=1;i--) printf "%s ", $$i}'),$(STACK))

.PHONY: init plan apply destroy output validate fmt apply-all destroy-all show

init:
	@for s in $(STACK_LIST) ; do \
		echo "== terraform init $$s (ENV=$(ENV)) =="; \
		# build per-stack key from envs/common.tfvars (state_prefix) and current ENV/stack
		KEY="$(PROJECT_NAME)/$(ENV)/$$s/terraform.tfstate"; \
		terraform -chdir=envs/$(ENV)/$$s init -input=false -reconfigure -backend-config=$(BACKEND_FILE) -backend-config="key=$$KEY" || exit 1; \
	done

plan:
	@for s in $(STACK_LIST) ; do \
		echo "== terraform plan $$s (ENV=$(ENV)) =="; \
		terraform -chdir=envs/$(ENV)/$$s plan -input=false -lock=true -var-file=$(COMMON_VARS) || exit 1; \
	done

apply:
	@for s in $(STACK_LIST) ; do \
		echo "== terraform apply $$s (ENV=$(ENV)) =="; \
		terraform -chdir=envs/$(ENV)/$$s apply -input=false -lock=true -auto-approve -var-file=$(COMMON_VARS) || exit 1; \
	done

destroy:
	@for s in $(REVERSE_STACKS) ; do \
		echo "== terraform destroy $$s (ENV=$(ENV)) =="; \
		terraform -chdir=envs/$(ENV)/$$s destroy -input=false -lock=true -auto-approve -var-file=$(COMMON_VARS) || exit 1; \
	done

output:
	@for s in $(STACK_LIST) ; do \
		echo "== terraform output $$s (ENV=$(ENV)) =="; \
		terraform -chdir=envs/$(ENV)/$$s output -json || true; \
	done

validate:
	@for s in $(STACK_LIST) ; do \
		echo "== terraform validate $$s (ENV=$(ENV)) =="; \
		terraform -chdir=envs/$(ENV)/$$s validate || exit 1; \
	done

fmt:
	@for s in $(STACK_LIST) ; do \
		echo "== terraform fmt $$s (ENV=$(ENV)) =="; \
		terraform -chdir=envs/$(ENV)/$$s fmt -recursive || exit 1; \
	done

show:
	@for s in $(STACK_LIST) ; do \
		echo "== terraform show $$s (ENV=$(ENV)) =="; \
		terraform -chdir=envs/$(ENV)/$$s show || true; \
	done

# Aliases
apply-all: ; @$(MAKE) apply STACK=all ENV=$(ENV)
destroy-all: ; @$(MAKE) destroy STACK=all ENV=$(ENV)

# -------- Terraform Orchestrator Makefile --------
ENV            ?= dev
PROJECT_NAME   ?= proj
STACK          ?= all
DEV_STACKS         := network eks cicd dns
PROD_STACKS        := network eks dns
STAGGED_STACKS     := network eks dns
STACKS         := $(if $(filter prod,$(ENV)),$(PROD_STACKS),$(if $(filter stagged,$(ENV)),$(STAGGED_STACKS),$(DEV_STACKS)))

BACKEND_FILE   := ../../backend.hcl
COMMON_VARS    := ../$(ENV)-common.tfvars

# If STACK=all -> use STACKS; else -> just the specific stack
STACK_LIST     := $(if $(filter all,$(STACK)),$(STACKS),$(STACK))
# Reverse order for destroy-all
REVERSE_STACKS := $(if $(filter all,$(STACK)),$(shell echo $(STACKS) | awk '{for(i=NF;i>=1;i--) printf "%s ", $$i}'),$(STACK))

.PHONY: init plan apply destroy output validate fmt show access-guide ssm-aliases

init:
	@for s in $(STACK_LIST) ; do \
		echo "== terraform init $$s (ENV=$(ENV)) =="; \
		KEY="$(PROJECT_NAME)/$(ENV)/$$s/terraform.tfstate"; \
		set -a; [ -f .env ] && . ./.env || true; set +a; \
		terraform -chdir=envs/$(ENV)/$$s init -input=false -reconfigure -backend-config=$(BACKEND_FILE) -backend-config="key=$$KEY" || exit 1; \
	done

plan:
	@for s in $(STACK_LIST) ; do \
	echo "== terraform plan $$s (ENV=$(ENV)) =="; \
	set -a; [ -f .env ] && . ./.env || true; set +a; \
	if [ "$$s" = "dns" ] && [ -z "$$TF_VAR_cloudflare_api_token" ]; then \
	  if command -v infisical >/dev/null 2>&1; then \
	    export TF_VAR_cloudflare_api_token="$$(infisical secrets get cloudflare_api_token --projectId="$${INFISICAL_PROJECT_ID}" --env="$(ENV)" --plain)"; \
	  fi; \
	fi; \
	terraform -chdir=envs/$(ENV)/$$s plan -input=false -lock=true -var-file=$(COMMON_VARS) || exit 1; \
	done

apply:
	@for s in $(STACK_LIST) ; do \
	echo "== terraform apply $$s (ENV=$(ENV)) =="; \
	set -a; [ -f .env ] && . ./.env || true; set +a; \
	if [ "$$s" = "dns" ] && [ -z "$$TF_VAR_cloudflare_api_token" ]; then \
	  if command -v infisical >/dev/null 2>&1; then \
	    export TF_VAR_cloudflare_api_token="$$(infisical secrets get cloudflare_api_token --projectId="$${INFISICAL_PROJECT_ID}" --env="$(ENV)" --plain)"; \
	  fi; \
	fi; \
	terraform -chdir=envs/$(ENV)/$$s apply -input=false -lock=true -auto-approve -var-file=$(COMMON_VARS) || exit 1; \
	done

destroy:
	@for s in $(REVERSE_STACKS) ; do \
	echo "== terraform destroy $$s (ENV=$(ENV)) =="; \
	set -a; [ -f .env ] && . ./.env || true; set +a; \
	if [ "$$s" = "dns" ] && [ -z "$$TF_VAR_cloudflare_api_token" ]; then \
	  if command -v infisical >/dev/null 2>&1; then \
	    export TF_VAR_cloudflare_api_token="$$(infisical secrets get cloudflare_api_token --projectId="$${INFISICAL_PROJECT_ID}" --env="$(ENV)" --plain)"; \
	  fi; \
	fi; \
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

# Generate access guide with all infrastructure details
access-guide:
	@echo "Generating infrastructure access guide for $(ENV)..."
	@./scripts/generate-access-commands.sh $(ENV)

# Generate SSM port-forward aliases
ssm-aliases:
	@echo "Generating SSM port-forward aliases for $(ENV)..."
	@./scripts/generate-ssm-aliases.sh $(ENV)
	@echo ""
	@echo "To activate aliases, run:"
	@echo "  source ~/.ssm-aliases-$(ENV)"

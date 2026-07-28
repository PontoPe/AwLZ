SHELL := /bin/bash
TF_DIRS := $(shell find live modules -name '*.tf' -exec dirname {} \; 2>/dev/null | sort -u)

.PHONY: help bootstrap fmt lint sec plan apply evidence cost clean

help: ## show targets
	@grep -hE '^[a-z-]+:.*##' $(MAKEFILE_LIST) | sed 's/:.*##/\t/' | column -t -s $$'\t'

bootstrap: ## create the remote state bucket (run once, starts on a local backend)
	cd live/bootstrap && terraform init && terraform apply -var-file=terraform.tfvars

fmt: ## format all terraform
	terraform fmt -recursive

lint: ## tflint across modules
	tflint --recursive

sec: ## static security analysis
	trivy config . --severity HIGH,CRITICAL --exit-code 1
	checkov -d . --quiet --compact

plan: ## plan a stack: make plan STACK=live/org-root
	cd $(STACK) && terraform init -upgrade && terraform plan -out=tfplan

apply: ## apply a planned stack
	cd $(STACK) && terraform apply tfplan

evidence: ## export Security Hub CIS score to docs/evidence/
	./scripts/export-cis-score.sh

cost: ## estimate monthly cost
	infracost breakdown --path .

clean:
	find . -name '.terraform' -type d -prune -exec rm -rf {} + ; find . -name 'tfplan' -delete

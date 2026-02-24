# Cost Sentinel Makefile
# Usage:
#   make dev-init
#   make dev-update
#   make lint
#   make ci-test
#   make ci-simulate
#   make clean
#   make build
#   make tf-init
#   make tf-fmt
#   make tf-validate
#   make tf-plan
#   make tf-apply
#   make tf-destroy

SHELL := /bin/bash

PYTHON ?= python3
VENV_DIR ?= .venv
DIST_DIR ?= dist
LAMBDA_ZIP ?= $(DIST_DIR)/ingestor.zip

TF_ENV ?= dev
TF_DIR := infra/envs/$(TF_ENV)

TERRAFORM_VERSION := 1.7.5
CODEBUILD_IMAGE   := public.ecr.aws/codebuild/standard:7.0

.DEFAULT_GOAL := ci-test

.PHONY: help
help:
	@echo "Targets:"
	@echo "  dev-init         Create venv, install dev deps, install pre-commit hooks"
	@echo "  dev-update       Update dev deps"
	@echo "  check-tfversion  Checks that the current local system Terraform version matches the project version"
	@echo "  lint             Run pre-commit on all files"
	@echo "  ci-test          Runs CI testing after cleaning .terraform directory"
	@echo "  ci-simulate      Runs CI testing in a Docker container to simulate CodeBuild run environment"
	@echo "  clean            Recursively removes .terraform/ folders and lock files"
	@echo "  build            Package Lambda into $(LAMBDA_ZIP)"
	@echo "  tf-init          Terraform init in infra/envs/$(TF_ENV)"
	@echo "  tf-fmt           Terraform fmt (repo)"
	@echo "  tf-validate      Terraform validate (env only, backend disabled)"
	@echo "  tf-plan          Terraform plan (env) (requires backend config if used)"
	@echo "  tf-apply         Terraform apply (env)"
	@echo "  tf-destroy       Terraform destroy (env)"
	@echo ""
	@echo "Vars:"
	@echo "  TF_ENV=dev|stage|prod  (default: dev)"
	@echo "  PYTHON=python3         (default: python3)"

# ----------------------------
# Local dev environment
# ----------------------------
.PHONY: dev-init
dev-init: $(VENV_DIR)/bin/activate
	@source $(VENV_DIR)/bin/activate && \
		pip install -U pip && \
		pip install -r requirements-dev.txt && \
		pre-commit install
	@echo "Dev environment ready. Activate with: source $(VENV_DIR)/bin/activate"

.PHONY: dev-update
dev-update: $(VENV_DIR)/bin/activate
	@source $(VENV_DIR)/bin/activate && \
		pip install -U pip && \
		pip install -U -r requirements-dev.txt

.PHONY: check-terraform-version
check-terraform-version:
	@REQUIRED=$$(cat .terraform-version); \
	CURRENT=$$(terraform version -json | jq -r '.terraform_version'); \
	if [ "$$REQUIRED" != "$$CURRENT" ]; then \
	  echo "Terraform version mismatch: required $$REQUIRED but found $$CURRENT"; \
	  exit 1; \
	fi

.PHONY: lint
lint: $(VENV_DIR)/bin/activate
	@source $(VENV_DIR)/bin/activate && pre-commit run --all-files


.PHONY: clean
clean:
	@echo "Removing .terraform directories..."
	@find . -type d -name ".terraform" -prune -exec rm -rf {} +
	@echo "Removing .terraform.lock.hcl files..."
	@find . -type f -name ".terraform.lock.hcl" -delete
	@echo "Clean complete."


# ----------------------------
# Build Lambda artifact
# ----------------------------
.PHONY: build
build:
	rm -rf $(DIST_DIR)
	mkdir -p $(DIST_DIR)
	cd app/ingestor && zip -r ../../$(LAMBDA_ZIP) handler.py requirements.txt >/dev/null
	@echo "Built: $(LAMBDA_ZIP)"


# ----------------------------
# Terraform helpers
# ----------------------------
.PHONY: tf-fmt
tf-fmt:
	terraform fmt -recursive

.PHONY: tf-init
tf-init:
	cd $(TF_DIR) && terraform init

.PHONY: tf-validate
tf-validate:
	cd $(TF_DIR) && terraform init -backend=false && terraform validate

.PHONY: tf-plan
tf-plan: build
	cd $(TF_DIR) && terraform plan

.PHONY: tf-apply
tf-apply: build
	cd $(TF_DIR) && terraform apply

.PHONY: tf-destroy
tf-destroy:
	cd $(TF_DIR) && terraform destroy

# Convenience: full local check
.PHONY: check
check: lint tf-validate
	@echo "All checks passed."


# ----------------------------
# Testing targets
# ----------------------------
.PHONY: ci-test
ci-test:
	rm -rf infra/modules/sentinel/tests/**/.terraform \
	       infra/modules/sentinel/tests/**/.terraform.lock.hcl
	cd infra/modules/sentinel/tests/basic && terraform init -backend=false && terraform test
	cd infra/modules/sentinel/tests/nodashboard && terraform init -backend=false && terraform test

.PHONY: ci-simulate
ci-simulate:
	@echo "Running CI simulation in Docker..."
	docker run --rm -it \
		-v "$$(pwd)":/workspace \
		-w /workspace \
		$(CODEBUILD_IMAGE) \
		bash -lc '\
			set -e; \
			echo "Installing Terraform $(TERRAFORM_VERSION)..."; \
			curl -sSLo /tmp/terraform.zip https://releases.hashicorp.com/terraform/$(TERRAFORM_VERSION)/terraform_$(TERRAFORM_VERSION)_linux_amd64.zip; \
			unzip -o /tmp/terraform.zip -d /usr/local/bin; \
			terraform -version; \
			export TF_IN_AUTOMATION=true; \
			echo "Running clean..."; \
			find . -type d -name ".terraform" -prune -exec rm -rf {} +; \
			find . -type f -name ".terraform.lock.hcl" -delete; \
			echo "Running tests..."; \
			cd infra/modules/sentinel/tests/basic && terraform init -backend=false && terraform test; \
			cd ../nodashboard && terraform init -backend=false && terraform test; \
			echo "CI simulation complete."; \
		'

.PHONY: integration-test
integration-test:
	@AWS_REGION=$${AWS_REGION:-us-east-1} \
	LAMBDA_FUNCTION_NAME=$${LAMBDA_FUNCTION_NAME:-cost-sentinel-dev-ingestor} \
	DASHBOARD_BUCKET_NAME=$${DASHBOARD_BUCKET_NAME}
	./scripts/integration_test_lambda.sh

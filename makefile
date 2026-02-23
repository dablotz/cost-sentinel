# Cost Sentinel Makefile
# Usage:
#   make dev-init
#   make lint
#   make build
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

.PHONY: help
help:
	@echo "Targets:"
	@echo "  dev-init     Create venv, install dev deps, install pre-commit hooks"
	@echo "  dev-update   Update dev deps"
	@echo "  lint         Run pre-commit on all files"
	@echo "  ci-test      Runs CI testing after cleaning .terraform directory"
	@echo "  build        Package Lambda into $(LAMBDA_ZIP)"
	@echo "  tf-init      Terraform init in infra/envs/$(TF_ENV)"
	@echo "  tf-fmt       Terraform fmt (repo)"
	@echo "  tf-validate  Terraform validate (env only, backend disabled)"
	@echo "  tf-plan      Terraform plan (env) (requires backend config if used)"
	@echo "  tf-apply     Terraform apply (env)"
	@echo "  tf-destroy   Terraform destroy (env)"
	@echo ""
	@echo "Vars:"
	@echo "  TF_ENV=dev|stage|prod  (default: dev)"
	@echo "  PYTHON=python3         (default: python3)"

# ----------------------------
# Local dev environment
# ----------------------------
$(VENV_DIR)/bin/activate:
	$(PYTHON) -m venv $(VENV_DIR)

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

.PHONY: lint
lint: $(VENV_DIR)/bin/activate
	@source $(VENV_DIR)/bin/activate && pre-commit run --all-files

.PHONY: ci-test
ci-test:
	rm -rf infra/modules/sentinel/tests/**/.terraform \
	       infra/modules/sentinel/tests/**/.terraform.lock.hcl
	cd infra/modules/sentinel/tests/basic && terraform init -backend=false && terraform test
	cd infra/modules/sentinel/tests/nodashboard && terraform init -backend=false && terraform test


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

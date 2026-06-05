terraform {
  # Partial config: bucket/key/region/dynamodb_table supplied at init time
  # via -backend-config (see infra/bootstrap/buildspec-deploy-prod.yml).
  # State key is cost-sentinel/prod.tfstate (separate from dev).
  backend "s3" {}
}

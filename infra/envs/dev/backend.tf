terraform {
  # Partial config: bucket/key/region/dynamodb_table supplied at init time
  # via -backend-config (see infra/bootstrap/buildspec-deploy-dev.yml).
  backend "s3" {}
}

# Mock provider means: plan without AWS access or credentials.
mock_provider "aws" {}

run "plan" {
  command = plan

  assert {
    condition     = module.sut.dashboard_bucket_name == null
    error_message = "dashboard_bucket should be null when dashboard is disabled."
  }
}

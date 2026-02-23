# Mock provider means: plan without AWS access or credentials.
mock_provider "aws" {}

run "plan" {
  command = plan

  # Basic sanity: outputs exist (adjust names to your real outputs)
  assert {
    condition     = module.sut.alerts_bucket != ""
    error_message = "alerts_bucket_name output should not be empty."
  }

  # Dashboard bucket should be enabled in this test harness
  assert {
    condition     = module.sut.dashboard_bucket_name != ""
    error_message = "dashboard_bucket_name output should not be empty when enabled."
  }
}

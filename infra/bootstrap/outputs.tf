output "connection_arn" {
  value = aws_codestarconnections_connection.github.arn
}

output "pipeline_name" {
  value = aws_codepipeline.pipeline.name
}

output "tf_state_bucket" {
  value = aws_s3_bucket.tfstate.bucket
}

output "artifact_bucket" {
  value = aws_s3_bucket.artifacts.bucket
}
